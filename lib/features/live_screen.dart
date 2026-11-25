import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/device.dart';
import '../core/analytics.dart';
import '../core/media/audio_player_service.dart';
import '../core/media/embed_video.dart';
import '../core/media/hls_video_player.dart';
import '../core/media/tv_youtube.dart';
import '../core/media/offline.dart';
import '../core/media/tv_file.dart';
import '../core/media/web_fullscreen.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/branding.dart';
import '../data/tv_schedule.dart';
import 'live_chat.dart';
import 'shell.dart';
import 'tv_overlay.dart';

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

  /// Bouton « Agrandir » : la TV en grand dans l'appli (vidéo + logo + bandeau d'un seul bloc).
  /// null = automatique (en grand quand le téléphone est tourné).
  bool? _bigOverride;
  bool? _lastLandscape;

  /// Téléviseur : bandeau « En ce moment / À suivre » affiché quelques secondes à la télécommande.
  bool _tvInfo = false;
  Timer? _tvInfoTimer;
  void _showTvInfo() {
    _tvInfoTimer?.cancel();
    setState(() => _tvInfo = true);
    _tvInfoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _tvInfo = false);
    });
  }

  /// Touches de la télécommande sur la chaîne en plein écran.
  KeyEventResult _onRemoteKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // Retour : on quitte le plein écran pour le menu (Samsung / LG dans le navigateur : Échap / Retour).
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.browserBack || k == LogicalKeyboardKey.backspace) {
      if (kIsWeb) {
        setState(() => _bigOverride = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // Android : géré par le bouton Retour du système (PopScope)
    }
    final info = <LogicalKeyboardKey>{
      LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA,
      LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.info, LogicalKeyboardKey.contextMenu,
    };
    if (info.contains(k)) {
      _showTvInfo();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _offKey = '';
  String? _lastPlan;

  /// Réserve hors connexion : programme en cours, suivant, toute la playlist en boucle
  /// et les rendez-vous des prochaines 24 h sont téléchargés à l'avance.
  void _sendPlan(TvSchedule schedule, TvSlot? slot, TvSlot? next, Size size) {
    final seen = <String>{};
    final items = <Map<String, String>>[];
    // Réserve réservée aux téléphones (une seule qualité, ≈ 480p) ; ordinateur et tablette lisent en direct
    // et une liste vide efface ce qui aurait été gardé.
    // Appli installée : tous les appareils gardent les vidéos. Web : téléphones seulement (en pause).
    final phone = !kIsWeb || isPhone(context);
    void add(TvProgram? p) {
      if (!phone || p == null || p.isYoutube || p.videoUrl.trim().isEmpty) return;
      final url = _phoneQuality(p.fileUrl, size);
      if (seen.add(url)) items.add({'url': url, 'title': p.title});
    }
    add(slot?.program);
    add(next?.program);
    // Les pubs des films passent aussi par la réserve.
    if (slot != null) schedule.adsOf(slot.show).forEach(add);
    for (final p in schedule.loop) {
      add(p);
      schedule.adsOf(p).forEach(add);
    }
    final now = _now();
    for (final p in schedule.fixed) {
      final s = p.startAt;
      if (s == null) continue;
      if (p.repeatDaily || p.repeatWeekly || (s.isAfter(now.subtract(const Duration(hours: 1))) && s.isBefore(now.add(const Duration(hours: 24))))) {
        add(p);
        schedule.adsOf(p).forEach(add);
      }
    }
    final json = jsonEncode(items);
    if (json == _lastPlan) return;
    _lastPlan = json;
    offlinePlan(json);
  }

  List<TvProgram>? _progs;
  TvChannel? _chan;
  String? _appliedSig, _pendingSig;
  Timer? _settle;

  static String _sigOf(List<TvProgram> ps, TvChannel c) =>
      '${c.status}|${c.anchor.millisecondsSinceEpoch}|${c.pausedAt?.millisecondsSinceEpoch}|${c.loopRepeat}|' +
      ps.map((p) => '${p.id}:${p.position}:${p.duration.inSeconds}:${p.startAt?.millisecondsSinceEpoch}:${p.repeatDaily}:${p.repeatWeekly}:${p.isPriority}:${p.kind}:${p.bandAnim}:${p.chartRank}:${p.voiceUrl}:${p.artist}:${p.song}:${p.airExtra.inSeconds}:${p.breaksSig}:${p.videoUrl}').join(',');

  void _settleSchedule(List<TvProgram> ps, TvChannel c) {
    final sig = _sigOf(ps, c);
    if (_progs == null || (ps.isNotEmpty && _progs!.isEmpty)) {
      _progs = ps;
      _chan = c;
      _appliedSig = sig;
      return;
    }
    if (sig == _appliedSig) {
      _settle?.cancel();
      _pendingSig = null;
      return;
    }
    if (sig == _pendingSig) return;
    _pendingSig = sig;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _progs = ps;
        _chan = c;
        _appliedSig = sig;
        _pendingSig = null;
      });
    });
  }

  void _toggleBig(bool now) => setState(() => _bigOverride = now ? false : true);
  // L'écran TV entier (vidéo + habillage) : déplacé tel quel quand on tourne le téléphone,
  // la vidéo ne se recharge pas et le logo / bandeau restent dessus.
  final _screenKey = GlobalKey();

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
      final st = offlineStatus();
      final offKey = st == null ? '' : '${st.ready}/${st.total}/${st.busy}';
      if ((end != null && !_now().isBefore(end)) || tvYoutubeMuted != _muted || offKey != _offKey) {
        _offKey = offKey;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tvInfoTimer?.cancel();
    _settle?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// Prévient la coque de l'appli qu'il faut cacher (ou réafficher) les menus.
  void _syncImmersive(bool value) {
    if (ref.read(immersiveProvider) == value) return;
    setPageImmersive(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(immersiveProvider.notifier).state = value;
    });
  }

  /// Téléphone : départ en basse qualité (≈ 360p, Cloudflare), puis qualité automatique selon la connexion pour qu'elle passe sans s'arrêter sur les connexions mobiles.
  /// Tablette, ordinateur et TV gardent la qualité automatique (jusqu'à 1080p).
  /// Téléphone : on regarde la taille de la fenêtre ET celle de l'écran de l'appareil
  /// (Safari en « version ordinateur » annonce une fenêtre plus grande que le téléphone).
  static bool isPhone(BuildContext context) {
    if (MediaQuery.sizeOf(context).shortestSide < 600) return true;
    try {
      final d = View.of(context).display;
      final s = d.size / d.devicePixelRatio;
      return s.shortestSide > 0 && s.shortestSide < 600;
    } catch (_) {
      return false;
    }
  }

  String _phoneQuality(String url, Size size) {
    final cf = url.contains('videodelivery.net') || url.contains('cloudflarestream.com');
    if (!cf || !isPhone(context) || url.contains('clientBandwidthHint')) return url;
    return '$url${url.contains('?') ? '&' : '?'}clientBandwidthHint=0.8';
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
    // Téléviseur : choisir « TV » dans le menu remet la chaîne en plein écran.
    ref.listen<int>(tvFullscreenProvider, (_, __) {
      if (_bigOverride != null) setState(() => _bigOverride = null);
    });
    final live = ref.watch(liveStreamProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final liveProgs = ref.watch(tvProgramsProvider).valueOrNull ?? const <TvProgram>[];
    final liveChan = ref.watch(tvChannelProvider).valueOrNull ?? const TvChannel();
    // La régie modifie la grille et l'horloge de la boucle en deux messages séparés :
    // on attend qu'ils soient arrivés tous les deux (1,5 s de calme) avant d'en tenir compte,
    // pour que l'image ne saute pas entre les deux.
    _settleSchedule(liveProgs, liveChan);
    final programs = _progs ?? liveProgs;
    final channel = _chan ?? liveChan;
    final branding = ref.watch(brandingProvider).valueOrNull ?? const Branding();
    // Base pas encore à jour, ou hors connexion sans copie : pas de jour spécial.
    final specialDays = ref.watch(tvSpecialDaysProvider).valueOrNull ?? const <TvSpecialDay>[];
    _clock = ref.watch(serverClockOffsetProvider).valueOrNull ?? Duration.zero;
    _muted = tvYoutubeMuted;
    // Le son s'arrête dès qu'on quitte la page TV (sauf en « audio seul »).
    final onTv = ref.watch(currentTabProvider) == AppTab.tv;
    final size = MediaQuery.sizeOf(context);
    final phone = isPhone(context);
    final landscape = size.width > size.height && phone;
    // Smart TV / ordinateur (1920×1080) : la TV prend toute la largeur de l'écran.
    final bigScreen = size.width >= 1280 && size.width > size.height;
    return live.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Connexion impossible pour le moment.', style: TextStyle(color: AppColors.muted))),
      data: (live) {
        // Un vrai direct (OBS) passe devant la programmation ; sinon, la chaîne 24 h/24.
        final onAir = live != null && live.canPlay;
        final schedule = TvSchedule(programs, anchor: channel.anchor, specialDays: specialDays, loopRepeat: channel.loopRepeat);
        final now = _now();
        // Régie : chaîne arrêtée = écran d'attente ; en pause = « Nous revenons dans un instant ».
        if (!onAir && channel.isPaused && !schedule.isEmpty) {
          _slotEnd = null;
          _syncImmersive(false);
          return const _Paused();
        }
        final slot = onAir || channel.isStopped ? null : schedule.at(now);
        // Écran d'attente (playlist terminée, boucle décochée) : on se réveille au prochain rendez-vous.
        final waitNext = slot == null && !onAir && !channel.isStopped ? schedule.nextFixedAfter(now) : null;
        _slotEnd = slot?.end ?? waitNext?.start;
        final canPlay = onAir || slot != null;
        // Tourner le téléphone remet le mode automatique.
        if (_lastLandscape != landscape) {
          _lastLandscape = landscape;
          _bigOverride = null;
        }
        // Téléphone tourné : toujours en grand. Debout : en grand seulement avec le bouton « Agrandir ».
        // Téléviseur : la chaîne est en plein écran par défaut (Retour = menu).
        final tv = isTvDevice;
        final immersive = canPlay && onTv && !_audioOnly && (landscape || _bigOverride == true || (tv && _bigOverride != false));
        _syncImmersive(immersive);
        if (!canPlay) return _Offline(live: live, nextProgram: waitNext);
        final next = slot == null ? null : schedule.after(slot);
        // « À suivre » : le prochain programme (pas la pub ni la suite du même film).
        final upNext = slot == null ? null : schedule.nextShow(slot);
        if (!onAir) _sendPlan(schedule, slot, next, size);
        final youtube = slot != null && slot.program.isYoutube;
        // Ce qui s'affiche sous la TV : le direct, ou le programme en cours.
        final LiveStream l = onAir
            ? live!
            : LiveStream(id: 'tv', title: live?.title ?? 'Conacce TV', isLive: false, messageTitle: slot!.show.title);
        final Widget player;
        if (!onTv) {
          player = const AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Colors.black));
        } else if (onAir && l.isLink) {
          final embed = l.liveEmbedUrl;
          player = embed != null
              ? EmbedVideo(key: ValueKey(embed), embedUrl: embed, sourceUrl: l.liveUrl!)
              : _ExternalLive(url: l.liveUrl!, source: l.source);
        } else if (onAir) {
          player = HlsVideoPlayer(key: _playerKey, url: l.hlsUrl!, isLive: true, onStarted: Analytics.liveView, expanded: immersive, onExpand: landscape ? null : () => _toggleBig(immersive));
        } else if (youtube) {
          player = TvYoutubeSurface(key: _tvKey, videoId: slot!.program.youtubeId!, slotKey: slot.key, position: () => slot!.positionAt(_now()));
        } else {
          final nx = next?.program;
          player = TvFileSurface(
            key: const ValueKey('tv-file'),
            url: _phoneQuality(slot!.program.fileUrl, size),
            // Appli installée : la vidéo gardée dans le téléphone passe en priorité (marche sans internet).
            localFile: offlineLocalFile(slot.program.fileUrl),
            slotKey: slot.key,
            position: () => slot!.positionAt(_now()),
            remaining: () => slot!.end.difference(_now()),
            nextUrl: nx != null && !nx.isYoutube ? _phoneQuality(nx.fileUrl, size) : null,
            expanded: immersive,
            onExpand: landscape ? null : () => _toggleBig(immersive),
          );
        }
        // Téléphone tourné : la vidéo occupe tout l'écran.
        // Habillage de la chaîne (logo, bandeau, bande artiste) par-dessus l'image.
        final overlay = Positioned.fill(child: TvOverlay(branding: branding, now: _now, slot: slot));
        final screen = Stack(key: _screenKey, children: [
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
                  if (!_audioOnly && onTv) overlay,
                  // Programme YouTube : la vidéo garde les touchers pour elle, le bouton reste donc affiché.
                  if (youtube && onTv && !_audioOnly && !landscape)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Material(
                        color: const Color(0x66000000),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: immersive ? 'Réduire' : 'Agrandir',
                          icon: Icon(immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white70),
                          onPressed: () => _toggleBig(immersive),
                        ),
                      ),
                    ),
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
                ]);
        if (immersive && tv) {
          // Téléviseur : la chaîne en plein écran, pilotée à la télécommande.
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _bigOverride = false);
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: _onRemoteKey,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  Center(child: screen),
                  _TvInfoBar(
                    visible: _tvInfo,
                    now: onAir ? (l.messageTitle ?? l.title) : slot!.show.title,
                    live: onAir,
                    nextTitle: upNext?.show.title,
                    nextAt: upNext?.segStart,
                  ),
                ]),
              ),
            ),
          );
        }
        if (immersive) {
          // Un geste vers le bas (ou le bouton « Réduire ») ramène l'écran normal.
          return GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 300) setState(() => _bigOverride = false);
            },
            child: ColoredBox(color: Colors.black, child: Center(child: screen)),
          );
        }
        // La TV toujours entière en haut ; la page défile, rien n'est coupé.
        // Sous la phrase d'accueil : un petit fil de commentaires, puis la zone pour écrire.
        return ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: 110),
          children: [
            MaxWidth(
              maxWidth: bigScreen ? size.width : 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                screen,
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
                    // Jour spécial en cours (Noël, Pâques, congrès…) : son nom sous la TV.
                    for (final d in specialDays.where((d) => d.covers(now.toUtc())).take(1)) ...[
                      const SizedBox(height: 4),
                      Text('★ ${d.name}', style: const TextStyle(color: AppColors.sunYellow, fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                    if (l.messageTitle != null) ...[
                      const SizedBox(height: 4),
                      Text(onAir ? l.messageTitle! : 'En ce moment · ${l.messageTitle!}', style: const TextStyle(color: AppColors.mist, fontSize: 13)),
                    ],
                    if (upNext != null && upNext.show.title.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'À suivre · ${DateFormat('HH:mm', 'fr_FR').format(upNext.segStart.toLocal())} · ${upNext.show.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      if (onAir && !l.isLink) ...[
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
                      if (!_audioOnly && !youtube && !(onAir && l.isLink) && pipSupported) ...[
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

/// Direct sur TikTok : TikTok n'autorise pas à intégrer un direct dans une autre appli.
class _ExternalLive extends StatelessWidget {
  const _ExternalLive({required this.url, required this.source});

  final String url;
  final String source;

  @override
  Widget build(BuildContext context) {
    final name = {'tiktok': 'TikTok', 'youtube': 'YouTube', 'facebook': 'Facebook'}[source] ?? 'le direct';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: AppColors.navyDeep,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('EN DIRECT SUR ${name.toUpperCase()}', style: AppTheme.title(size: 16, weight: FontWeight.w800)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text('Regarder le direct sur $name'),
            ),
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
  const _Offline({required this.live, this.nextProgram});

  final LiveStream? live;

  /// Prochain rendez-vous de la grille (écran d'attente quand la playlist ne tourne pas en boucle).
  final TvSlot? nextProgram;

  @override
  Widget build(BuildContext context) {
    final next = live?.nextLiveAt;
    final prog = nextProgram;
    if (prog != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
          child: MaxWidth(
            maxWidth: 520,
            child: Column(children: [
              const LogoShine(width: 260, radius: 6),
              const SizedBox(height: 24),
              Text('Conacce TV revient bientôt', style: AppTheme.title(size: 18, weight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              NavyCard(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Prochain programme à ${DateFormat('HH:mm', 'fr_FR').format(prog.start.toLocal())}',
                      style: AppTheme.title(size: 14, color: AppColors.sunYellow)),
                  if (prog.program.title.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(prog.program.title, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mist)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      );
    }
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


/// Téléviseur : bandeau en bas de l'écran, affiché quelques secondes quand on touche la télécommande.
class _TvInfoBar extends StatelessWidget {
  const _TvInfoBar({required this.visible, required this.now, required this.live, this.nextTitle, this.nextAt});

  final bool visible;
  final String now;
  final bool live;
  final String? nextTitle;
  final DateTime? nextAt;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: visible ? 1 : 0,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xE6050A30)]),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(live ? 'EN DIRECT' : 'EN CE MOMENT',
                  style: AppTheme.title(size: 14, weight: FontWeight.w800, color: live ? AppColors.live : AppColors.sunYellow).copyWith(letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(now, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 30, weight: FontWeight.w800, color: Colors.white)),
              if (nextTitle != null && nextTitle!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('À SUIVRE${nextAt == null ? '' : ' · ${two(nextAt!.hour)}:${two(nextAt!.minute)}'}  ·  $nextTitle',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mist, fontSize: 18)),
              ],
              const SizedBox(height: 14),
              const Text('Retour : menu de l’appli', style: TextStyle(color: AppColors.muted, fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }
}
