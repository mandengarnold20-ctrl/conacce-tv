import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'shell.dart';
import 'sermons_screen.dart';
import 'works_screen.dart';

/// Accueil : direct Conacce TV, Radio Dunamis FM, derniers cultes, Œuvres d'Or.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _go(WidgetRef ref, AppTab tab) => ref.read(currentTabProvider.notifier).state = tab;

  Future<void> _openBanner(BuildContext context, WidgetRef ref, HomeBanner b) async {
    switch (b.targetType) {
      case 'live':
        _go(ref, AppTab.tv);
      case 'radio':
        _go(ref, AppTab.radio);
      case 'sermon':
        final s = b.targetId == null ? null : await sermonById(b.targetId!);
        if (s != null && context.mounted) openSermon(context, s);
      case 'work':
        final w = b.targetId == null ? null : await workById(b.targetId!);
        if (w != null && context.mounted) openWork(context, w);
      case 'url':
        if (b.targetUrl != null) await launchUrl(Uri.parse(b.targetUrl!), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveStreamProvider).valueOrNull;
    final radio = ref.watch(radioProvider).valueOrNull;
    final banners = ref.watch(bannersProvider).valueOrNull ?? const [];
    final sermons = ref.watch(sermonsProvider(null));
    final works = ref.watch(worksProvider).valueOrNull ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bannersProvider);
        ref.invalidate(sermonsProvider);
        ref.invalidate(worksProvider);
        await ref.read(sermonsProvider(null).future).catchError((_) => <Sermon>[]);
      },
      child: ListView(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12, bottom: 110),
        children: [
          MaxWidth(
            maxWidth: 900,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const LogoShine(width: 150, radius: 3),
                  const Spacer(),
                ]),
              ),
              const SizedBox(height: 18),

              // Vidéos des cultes (à la place de l'ancien écran TV)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: sermons.when(
                  loading: () => const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator())),
                  error: (_, __) => const _FeaturedPlaceholder('Connexion impossible pour le moment.'),
                  data: (list) => list.isEmpty ? const _FeaturedPlaceholder('Les vidéos des cultes apparaîtront ici.') : _FeaturedSermon(sermon: list.first),
                ),
              ),
              if ((sermons.valueOrNull?.length ?? 0) > 1) ...[
                SectionTitle('Cultes enregistrés', onSeeAll: () => _go(ref, AppTab.sermons)),
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: (sermons.valueOrNull!.length - 1).clamp(0, 10),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => SizedBox(width: 210, child: SermonCard(sermon: sermons.valueOrNull![i + 1])),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Boutons TV et Radio, côte à côte
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Expanded(
                    child: _QuickButton(
                      icon: Icons.live_tv_rounded,
                      title: 'Conacce TV',
                      subtitle: live?.canPlay ?? false ? 'En direct maintenant' : 'Hors antenne',
                      on: live?.canPlay ?? false,
                      onTap: () => _go(ref, AppTab.tv),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickButton(
                      icon: Icons.radio_rounded,
                      title: radio?.name ?? 'Radio Dunamis FM',
                      subtitle: radio?.canPlay ?? false ? (radio?.currentShow ?? 'À l’antenne') : 'Hors antenne',
                      on: radio?.canPlay ?? false,
                      onTap: () => _go(ref, AppTab.radio),
                    ),
                  ),
                ]),
              ),

              if (banners.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 170,
                  child: PageView.builder(
                    controller: PageController(viewportFraction: .88),
                    itemCount: banners.length,
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        onTap: () => _openBanner(context, ref, banners[i]),
                        child: Stack(fit: StackFit.expand, children: [
                          NetCover(url: banners[i].imageUrl, radius: 18),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00080F43), Color(0xD9080F43)], stops: [.4, 1]),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(banners[i].title, style: AppTheme.title(size: 15)),
                              if (banners[i].subtitle != null) Text(banners[i].subtitle!, style: const TextStyle(color: AppColors.mist, fontSize: 12)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],

              if (works.isNotEmpty) ...[
                SectionTitle('Œuvres d’Or', onSeeAll: () => _go(ref, AppTab.works)),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: works.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => SizedBox(width: 110, child: WorkCover(work: works[i])),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Grande vignette du dernier culte publié.
class _FeaturedSermon extends StatelessWidget {
  const _FeaturedSermon({required this.sermon});

  final Sermon sermon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openSermon(context, sermon),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            NetCover(url: sermon.thumbnailUrl, radius: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00080F43), Color(0x99080F43)]),
              ),
            ),
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(gradient: AppColors.sunGradient, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: AppColors.navy, size: 34),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text(sermon.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 15)),
        if (sermon.speaker != null)
          Text(sermon.speaker!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mist, fontSize: 12)),
      ]),
    );
  }
}

class _FeaturedPlaceholder extends StatelessWidget {
  const _FeaturedPlaceholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.play_circle_outline_rounded, color: AppColors.mist, size: 44),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mist, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// Bouton compact (TV ou Radio) avec un point rouge quand c'est en cours.
class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.icon, required this.title, required this.subtitle, required this.on, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NavyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.navy, size: 22),
          ),
          if (on)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: AppColors.live, shape: BoxShape.circle, border: Border.all(color: AppColors.navyDeep, width: 2)),
              ),
            ),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 13)),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mist, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}
