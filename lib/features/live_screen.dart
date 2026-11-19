import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/analytics.dart';
import '../core/media/audio_player_service.dart';
import '../core/media/hls_video_player.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'live_chat.dart';
import 'shell.dart';

/// Conacce TV en direct : vidéo, bandeau orateur / message, audio seul, partage, soutien.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  bool _audioOnly = false;
  // Même lecteur en mode normal et en grand écran : la vidéo continue sans coupure.
  final _playerKey = GlobalKey();

  /// Prévient la coque de l'appli qu'il faut cacher (ou réafficher) les menus.
  void _syncImmersive(bool value) {
    if (ref.read(immersiveProvider) == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(immersiveProvider.notifier).state = value;
    });
  }

  Future<void> _toggleAudio(LiveStream live) async {
    final audio = ref.read(audioPlayerServiceProvider);
    final enable = !_audioOnly;
    setState(() => _audioOnly = enable);
    if (enable) {
      Analytics.liveView();
      await audio.play(id: 'live', url: live.hlsUrl!, title: live.messageTitle ?? live.title, artist: 'Conacce TV', isLive: true);
    } else if (audio.currentId == 'live') {
      await audio.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveStreamProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    // Le son s'arrête dès qu'on quitte la page TV (sauf en « audio seul »).
    final onTv = ref.watch(currentTabProvider) == AppTab.tv;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && size.shortestSide < 600;
    return live.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Connexion impossible pour le moment.', style: TextStyle(color: AppColors.muted))),
      data: (l) {
        final canPlay = l != null && l.canPlay;
        final immersive = canPlay && onTv && landscape && !_audioOnly;
        _syncImmersive(immersive);
        if (l == null || !l.canPlay) return _Offline(live: l);
        final Widget player = onTv
            ? HlsVideoPlayer(key: _playerKey, url: l.hlsUrl!, isLive: true, onStarted: Analytics.liveView)
            : const AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Colors.black));
        // Téléphone tourné : la vidéo occupe tout l'écran.
        if (immersive) return ColoredBox(color: Colors.black, child: Center(child: player));
        // En haut : la TV, le titre et la phrase d'accueil. Au milieu : le fil des messages,
        // qui passe sous la phrase. En bas : la zone pour écrire, toujours à la même place.
        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final bottomPad = keyboard ? 8.0 : 110.0;
        return LayoutBuilder(builder: (context, box) {
          final headerMax = (box.maxHeight - MediaQuery.paddingOf(context).top - bottomPad - 112 - 150).clamp(0.0, double.infinity);
          return Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: bottomPad),
            child: MaxWidth(
              maxWidth: 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: headerMax),
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Stack(children: [
                  if (_audioOnly)
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ColoredBox(
                        color: AppColors.navyDeep,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const LogoShine(width: 200, radius: 4),
                          const SizedBox(height: 12),
                          Text('Écoute en audio seul', style: AppTheme.title(size: 13, color: AppColors.mist)),
                        ]),
                      ),
                    )
                  else
                    player,
                  if (!_audioOnly && (l.speaker != null || l.messageTitle != null))
                    Positioned(
                      left: 12,
                      bottom: 44,
                      child: IgnorePointer(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (l.speaker != null)
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              child: Text(l.speaker!.toUpperCase(), style: AppTheme.title(size: 12, weight: FontWeight.w800, color: AppColors.navy)),
                            ),
                          if (l.messageTitle != null)
                            Container(
                              decoration: const BoxDecoration(gradient: AppColors.sunGradient),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              child: Text(l.messageTitle!, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 11)),
                            ),
                        ]),
                      ),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(l.title.replaceAll(RegExp(r'\s*HD$'), ''), style: AppTheme.title(size: 20, weight: FontWeight.w800))),
                      const SizedBox(width: 8),
                      // Conacce TV HD
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(6)),
                        child: Text('HD', style: AppTheme.title(size: 12, weight: FontWeight.w800, color: AppColors.navy)),
                      ),
                    ]),
                    if (l.messageTitle != null) ...[
                      const SizedBox(height: 4),
                      Text(l.messageTitle!, style: const TextStyle(color: AppColors.mist, fontSize: 13)),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _Action(icon: _audioOnly ? Icons.videocam_rounded : Icons.headphones_rounded, label: _audioOnly ? 'Vidéo' : 'Audio seul', onTap: () => _toggleAudio(l))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Action(
                          icon: Icons.share_rounded,
                          label: 'Partager',
                          onTap: () => Share.share('Suivez ${l.title} en direct sur l’appli Conacce TV !'),
                        ),
                      ),
                      if (settings?.donationUrl != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Action(
                            icon: Icons.favorite_rounded,
                            label: 'Soutenir',
                            sun: true,
                            onTap: () => launchUrl(Uri.parse(settings!.donationUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ),
                      ],
                    ]),
                  ]),
                ),
                      const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 0), child: WelcomeSlogan()),
                    ]),
                  ),
                ),
                const Expanded(child: LiveCommentsFeed()),
                const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 4), child: LiveComposer()),
              ]),
            ),
          );
        });
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.sun = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool sun;

  @override
  Widget build(BuildContext context) {
    final fg = sun ? AppColors.navy : Colors.white;
    return Material(
      color: Colors.transparent,
      child: Ink(
        height: 62,
        decoration: BoxDecoration(
          gradient: sun ? AppColors.sunGradient : AppColors.cardGradient,
          borderRadius: BorderRadius.circular(14),
          border: sun ? null : Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Pas de direct en ce moment : image de la chaîne et prochain rendez-vous.
class _Offline extends StatelessWidget {
  const _Offline({required this.live});

  final LiveStream? live;

  @override
  Widget build(BuildContext context) {
    final next = live?.nextLiveAt;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
        child: MaxWidth(
          maxWidth: 520,
          child: Column(children: [
            const LogoShine(width: 260, radius: 6),
            const SizedBox(height: 24),
            Text('Pas de direct en ce moment', style: AppTheme.title(size: 18, weight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              live?.nextLiveInfo ?? 'Le prochain culte en direct sera annoncé ici. Revenez bientôt !',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.mist, height: 1.5),
            ),
            if (next != null && next.isAfter(DateTime.now())) ...[
              const SizedBox(height: 14),
              NavyCard(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_rounded, color: AppColors.sunYellow),
                  const SizedBox(width: 10),
                  Text(DateFormat("EEEE d MMMM 'à' HH'h'mm", 'fr_FR').format(next), style: AppTheme.title(size: 13)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
