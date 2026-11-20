import 'dart:async';

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
    final conacce = ref.watch(featuredVideosProvider);
    final sermons = ref.watch(sermonsProvider(('cultes', null)));
    final works = ref.watch(worksProvider).valueOrNull ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bannersProvider);
        ref.invalidate(sermonsProvider);
        ref.invalidate(featuredVideosProvider);
        ref.invalidate(worksProvider);
        await ref.read(sermonsProvider(('conacce', null)).future).catchError((_) => <Sermon>[]);
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
                  IconButton(
                    tooltip: 'Contact et messagerie',
                    onPressed: () => _go(ref, AppTab.contact),
                    icon: const Icon(Icons.mail_outline_rounded, color: Colors.white),
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // Grand écran : les vidéos de la Conacce, qui défilent toutes seules
              conacce.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator())),
                ),
                error: (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _FeaturedPlaceholder('Connexion impossible pour le moment.'),
                ),
                data: (list) => list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: _FeaturedPlaceholder('Les vidéos de la Conacce apparaîtront ici.'),
                      )
                    : _ConacceCarousel(items: list),
              ),
              // Petits écrans : les vidéos des cultes
              if ((sermons.valueOrNull?.length ?? 0) > 0) ...[
                SectionTitle('Cultes enregistrés', onSeeAll: () {
                  ref.read(videoSectionProvider.notifier).state = 'cultes';
                  _go(ref, AppTab.sermons);
                }),
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: sermons.valueOrNull!.length.clamp(0, 12),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => SizedBox(width: 210, child: SermonCard(sermon: sermons.valueOrNull![i])),
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

              // Contact et messagerie
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: NavyCard(
                  onTap: () => _go(ref, AppTab.contact),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.forum_rounded, color: AppColors.navy),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Écrivez-nous', style: AppTheme.title(size: 14)),
                        const SizedBox(height: 2),
                        const Text('Messagerie, site et e-mail de la CONACCE', style: TextStyle(color: AppColors.mist, fontSize: 12)),
                      ]),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Grand écran de l'accueil, comme la bannière d'un site web : les 7 dernières vidéos Conacce
/// défilent toutes seules (toutes les 5 s), au doigt ou avec les flèches.
class _ConacceCarousel extends StatefulWidget {
  const _ConacceCarousel({required this.items});

  final List<Sermon> items;

  @override
  State<_ConacceCarousel> createState() => _ConacceCarouselState();
}

class _ConacceCarouselState extends State<_ConacceCarousel> {
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  /// Relance le défilement automatique (après un geste, on repart pour 5 s).
  void _restart() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _go(_index + 1));
  }

  void _go(int i) {
    if (!mounted || !_pages.hasClients || widget.items.length < 2) return;
    final n = widget.items.length;
    _pages.animateToPage((i % n + n) % n, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.items.length > 1;
    Widget arrow(IconData icon, int delta) => Material(
          color: const Color(0x66080F43),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              _go(_index + delta);
              _restart();
            },
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: Colors.white, size: 22)),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: _pages,
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _restart();
                },
                itemBuilder: (context, i) => _FeaturedSermon(sermon: widget.items[i]),
              ),
              if (many) ...[
                Positioned(left: 8, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_left_rounded, -1))),
                Positioned(right: 8, top: 0, bottom: 0, child: Center(child: arrow(Icons.chevron_right_rounded, 1))),
              ],
            ]),
          ),
        ),
      ),
      if (many)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.items.length; i++)
              GestureDetector(
                onTap: () {
                  _go(i);
                  _restart();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _index ? AppColors.sunYellow : const Color(0x55FFFFFF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }
}

/// Une diapositive : l'image en plein cadre, le titre posé dessus en bas, et le bouton lecture.
class _FeaturedSermon extends StatelessWidget {
  const _FeaturedSermon({required this.sermon});

  final Sermon sermon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openSermon(context, sermon),
      child: Stack(fit: StackFit.expand, children: [
        NetCover(url: sermon.coverUrl, radius: 0),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00080F43), Color(0x00080F43), Color(0xE6080F43)],
              stops: [0, .45, 1],
            ),
          ),
        ),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(gradient: AppColors.sunGradient, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: AppColors.navy, size: 34),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Text(
            sermon.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.title(size: 15).copyWith(shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 6)]),
          ),
        ),
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
        alignment: Alignment.center,
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mist, fontSize: 13)),
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
