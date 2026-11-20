import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/analytics.dart';
import '../core/media/audio_player_service.dart';
import '../core/media/hls_video_player.dart';
import '../core/media/tv_youtube.dart';
import '../core/media/web_fullscreen.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/tv_schedule.dart';
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
  final _tvKey = GlobalKey();

  // Chaîne programmée : on change de programme pile à l'heure prévue.
  Duration _clock = Duration.zero;
  DateTime? _slotEnd;
  bool _muted = false;
  Timer? _ticker;

  DateTime _now() => DateTime.now().add(_clock);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final end = _slotEnd;
      if ((end != null && !_now().isBefore(end)) || tvYoutubeMuted != _muted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

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
    final programs = ref.watch(tvProgramsProvider).valueOrNull ?? const <TvProgram>[];
    final channel = ref.watch(tvChannelProvider).valueOrNull ?? const TvChannel();
    _clock = ref.watch(serverClockOffsetProvider).valueOrNull ?? Duration.zero;
    _muted = tvYoutubeMuted;
    // Le son s'arrête dès qu'on quitte la page TV (sauf en « audio seul »).
    final onTv = ref.watch(currentTabProvider) == AppTab.tv;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && size.shortestSide < 600;
    // Smart TV / ordinateur (1920×1080) : la TV prend toute la largeur de l'écran.
    final bigScreen = size.width >= 1280 && size.width > size.height;
    return live.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Connexion impossible pour le moment.', style: TextStyle(color: AppColors.muted))),
      data: (live) {
        // Un vrai direct (OBS) passe devant la programmation ; sinon, la chaîne 24 h/24.
        final onAir = live != null && live.canPlay;
        final schedule = TvSchedule(programs, anchor: channel.anchor);
        final now = _now();
        // Régie : chaîne arrêtée = écran d'attente ; en pause = « Nous revenons dans un instant ».
        if (!onAir && channel.isPaused && !schedule.isEmpty) {
          _slotEnd = null;
          _syncImmersive(false);
          return const _Paused();
        }
        final slot = onAir || channel.isStopped ? null : schedule.at(now);
        _slotEnd = slot?.end;
        final canPlay = onAir || slot != null;
        final immersive = canPlay && onTv && landscape && !_audioOnly;
        _syncImmersive(immersive);
        if (!canPlay) return _Offline(live: live);
        final next = slot == null ? null : schedule.after(slot);
        final youtube = slot != null && slot.program.isYoutube;
        // Ce qui s'affiche sous la TV : le direct, ou le programme en cours.
        final LiveStream l = onAir
            ? live!
            : LiveStream(id: 'tv', title: live?.title ?? 'Conacce TV', isLive: false, messageTitle: slot!.program.title);
        final Widget player;
        if (!onTv) {
          player = const AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Colors.black));
        } else if (onAir) {
          player = HlsVideoPlayer(key: _playerKey, url: l.hlsUrl!, isLive: true, onStarted: Analytics.liveView);
        } else if (youtube) {
          player = TvYoutubeSurface(key: _tvKey, videoId: slot!.program.youtubeId!, slotKey: slot.key, position: () => slot!.positionAt(_now()));
        } else {
          player = HlsVideoPlayer(key: ValueKey(slot!.key), url: slot.program.fileUrl, isLive: true, startAt: () => slot!.positionAt(_now()));
        }
        // Téléphone tourné : la vidéo occupe tout l'écran.
        if (immersive) return ColoredBox(color: Colors.black, child: Center(child: player));
        // La TV toujours entière en haut ; la page défile, rien n'est coupé.
        // Sous la phrase d'accueil : un petit fil de commentaires, puis la zone pour écrire.
        return ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: 110),
          children: [
            MaxWidth(
              maxWidth: bigScreen ? size.width : 1000,
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
                  if (onAir && !_audioOnly && (l.speaker != null || l.messageTitle != null))
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
                      Text(onAir ? l.messageTitle! : 'En ce moment · ${l.messageTitle!}', style: const TextStyle(color: AppColors.mist, fontSize: 13)),
                    ],
                    if (next != null && next.program.title.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'À suivre · ${DateFormat('HH:mm', 'fr_FR').format(next.start.toLocal())} · ${next.program.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      if (onAir) ...[
                        Expanded(child: _Action(icon: _audioOnly ? Icons.videocam_rounded : Icons.headphones_rounded, label: _audioOnly ? 'Vidéo' : 'Audio seul', onTap: () => _toggleAudio(l))),
                        const SizedBox(width: 10),
                      ],
                      // Le navigateur a coupé le son au démarrage : un toucher suffit pour l'activer.
                      if (youtube && _muted) ...[
                        Expanded(
                          child: _Action(
                            icon: Icons.volume_up_rounded,
                            label: 'Activer le son',
                            sun: true,
                            onTap: () {
                              tvYoutubeUnmute();
                              setState(() => _muted = false);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      // Mini-écran : la TV continue dans une petite fenêtre au-dessus des autres applis.
                      if (!_audioOnly && !youtube && pipSupported) ...[
                        Expanded(child: _Action(icon: Icons.picture_in_picture_alt_rounded, label: 'Mini-écran', onTap: togglePictureInPicture)),
                        const SizedBox(width: 10),
                      ],
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
                const LiveCommentsFeed(),
                const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: LiveComposer()),
              ]),
            ),
          ],
        );
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

/// La régie a mis la chaîne en pause.
class _Paused extends StatelessWidget {
  const _Paused();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
        child: MaxWidth(
          maxWidth: 520,
          child: Column(children: [
            const LogoShine(width: 260, radius: 6),
            const SizedBox(height: 24),
            Text('Nous revenons dans un instant', style: AppTheme.title(size: 18, weight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Conacce TV reprend très bientôt. Restez avec nous !',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.mist, height: 1.5),
            ),
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
