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
                  if (live?.canPlay ?? false) GestureDetector(onTap: () => _go(ref, AppTab.tv), child: const LiveBadge()),
                ]),
              ),
              const SizedBox(height: 18),

              // Carte du direct
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _LiveCard(live: live, onTap: () => _go(ref, AppTab.tv)),
              ),
              const SizedBox(height: 14),

              // Radio Dunamis FM
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: NavyCard(
                  onTap: () => _go(ref, AppTab.radio),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.radio_rounded, color: AppColors.navy),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(radio?.name ?? 'Radio Dunamis FM', style: AppTheme.title(size: 14)),
                        const SizedBox(height: 2),
                        Text(
                          radio?.canPlay ?? false ? (radio?.currentShow ?? 'En direct') : 'Hors antenne pour le moment',
                          style: const TextStyle(color: AppColors.mist, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: AppColors.navy),
                    ),
                  ]),
                ),
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

              SectionTitle('Cultes enregistrés', onSeeAll: () => _go(ref, AppTab.sermons)),
              SizedBox(
                height: 178,
                child: sermons.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const _Empty('Connexion impossible pour le moment.'),
                  data: (list) => list.isEmpty
                      ? const _Empty('Les premiers cultes arrivent bientôt.')
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: list.length.clamp(0, 10),
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => SizedBox(width: 210, child: SermonCard(sermon: list[i])),
                        ),
                ),
              ),

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

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.live, required this.onTap});

  final LiveStream? live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = live?.canPlay ?? false;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [AppColors.navy, AppColors.navyDeep]),
          boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          if (live?.offlineImageUrl != null) Positioned.fill(child: NetCover(url: live!.offlineImageUrl, radius: 0)),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x330B1463), Color(0xE6080F43)])),
            ),
          ),
          const Positioned(left: 0, right: 0, top: 46, child: Center(child: LogoShine(width: 230, radius: 4))),
          Positioned(left: 14, top: 14, child: on ? const LiveBadge() : const _Pill('HORS ANTENNE')),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Text(
                  on ? (live?.messageTitle ?? live?.title ?? 'Conacce TV') : (live?.nextLiveInfo ?? 'Prochain direct bientôt annoncé'),
                  style: AppTheme.title(size: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: Text(on ? 'Regarder' : 'Voir', style: AppTheme.title(size: 13, color: AppColors.navy)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: AppTheme.title(size: 10, weight: FontWeight.w700).copyWith(letterSpacing: 1)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: Text(text, style: const TextStyle(color: AppColors.muted)));
}
