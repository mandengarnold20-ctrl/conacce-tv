import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/analytics.dart';
import '../core/media/audio_player_service.dart';
import '../core/media/hls_video_player.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'downloads.dart';

String _sermonMeta(Sermon s) => [
      s.speaker,
      if (s.preachedOn != null) DateFormat('d MMM y', 'fr_FR').format(s.preachedOn!),
    ].whereType<String>().join(' · ');

void openSermon(BuildContext context, Sermon s, {DownloadedTrack? offline}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => SermonPlayerScreen(sermon: s, offline: offline)));
}

/// Onglet Cultes : enregistrements publiés par l'église, comme une chaîne vidéo.
class SermonsScreen extends ConsumerStatefulWidget {
  const SermonsScreen({super.key});

  @override
  ConsumerState<SermonsScreen> createState() => _SermonsScreenState();
}

class _SermonsScreenState extends ConsumerState<SermonsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Future<List<Sermon>>? _results;
  bool _offline = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _results = v.trim().length < 2 ? null : searchSermons(v.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final category = ref.watch(sermonCategoryProvider);
    final sermons = ref.watch(sermonsProvider(category));
    final downloads = ref.watch(downloadsProvider);

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            labelStyle: TextStyle(color: selected ? AppColors.navy : Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            selectedColor: AppColors.sunYellow,
            backgroundColor: const Color(0x660B1463),
            side: BorderSide(color: selected ? Colors.transparent : const Color(0x33FFFFFF)),
            shape: const StadiumBorder(),
          ),
        );

    Widget list;
    if (_results != null) {
      list = FutureBuilder<List<Sermon>>(
        future: _results,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final r = snap.data ?? const <Sermon>[];
          return r.isEmpty ? const _Message('Aucun culte trouvé.') : _SermonList(items: r);
        },
      );
    } else if (_offline) {
      list = downloads.items.isEmpty
          ? const _Message('Aucun culte téléchargé.\nOuvrez un culte puis touchez « Télécharger ».')
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
              children: [for (final t in downloads.items) SermonTile(sermon: t.item, offline: t)],
            );
    } else {
      list = sermons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _Message('Connexion impossible pour le moment.'),
        data: (items) => items.isEmpty ? const _Message('Aucun culte dans cette catégorie pour le moment.') : _SermonList(items: items),
      );
    }

    return MaxWidth(
      maxWidth: 900,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 12),
          child: Text('Cultes', style: AppTheme.title(size: 22, weight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher un culte, un thème, un orateur…',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _results = null);
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
            children: [
              chip('Tous', category == null && !_offline, () => setState(() {
                    _offline = false;
                    ref.read(sermonCategoryProvider.notifier).state = null;
                  })),
              for (final c in SermonCategory.values.where((c) => c != SermonCategory.autre))
                chip(c == SermonCategory.dimanche ? 'Dimanche' : c.label, category == c && !_offline, () => setState(() {
                      _offline = false;
                      ref.read(sermonCategoryProvider.notifier).state = c;
                    })),
              if (DownloadsController.supported) chip('Téléchargés', _offline, () => setState(() => _offline = true)),
            ],
          ),
        ),
        Expanded(child: list),
      ]),
    );
  }
}

class _SermonList extends StatelessWidget {
  const _SermonList({required this.items});

  final List<Sermon> items;

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
        itemCount: items.length,
        itemBuilder: (context, i) => SermonTile(sermon: items[i]),
      );
}

/// Ligne de culte : vignette + titre + orateur / date.
class SermonTile extends StatelessWidget {
  const SermonTile({super.key, required this.sermon, this.offline});

  final Sermon sermon;
  final DownloadedTrack? offline;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openSermon(context, sermon, offline: offline),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 150,
            height: 86,
            child: Stack(fit: StackFit.expand, children: [
              NetCover(url: sermon.thumbnailUrl, radius: 12),
              if (sermon.durationLabel != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
                    child: Text(sermon.durationLabel!, style: const TextStyle(fontSize: 11)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sermon.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
              const SizedBox(height: 4),
              Text(_sermonMeta(sermon), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mist, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                if (sermon.hasVideo) const _Tag('Vidéo', sun: true),
                if (sermon.hasAudio) const _Tag('Audio'),
                if (offline != null) const _Tag('Hors connexion'),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Carte verticale (accueil).
class SermonCard extends StatelessWidget {
  const SermonCard({super.key, required this.sermon});

  final Sermon sermon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openSermon(context, sermon),
      borderRadius: BorderRadius.circular(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 118,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            NetCover(url: sermon.thumbnailUrl, radius: 14),
            if (sermon.durationLabel != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
                  child: Text(sermon.durationLabel!, style: const TextStyle(fontSize: 11)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(sermon.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        Text('${sermon.category.label}${sermon.preachedOn == null ? '' : ' · ${DateFormat('d MMM', 'fr_FR').format(sermon.preachedOn!)}'}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.mist, fontSize: 11)),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.sun = false});

  final String text;
  final bool sun;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: sun ? const Color(0x2EF9CA22) : const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 11, color: sun ? AppColors.sunYellow : Colors.white)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.6)),
      );
}

/// Lecture d'un culte (vidéo ou audio), téléchargement hors connexion, partage.
class SermonPlayerScreen extends ConsumerStatefulWidget {
  const SermonPlayerScreen({super.key, required this.sermon, this.offline});

  final Sermon sermon;
  final DownloadedTrack? offline;

  @override
  ConsumerState<SermonPlayerScreen> createState() => _SermonPlayerScreenState();
}

class _SermonPlayerScreenState extends ConsumerState<SermonPlayerScreen> {
  late bool _audioOnly = widget.offline != null ? !widget.offline!.isVideo : !widget.sermon.hasVideo;

  Sermon get s => widget.sermon;

  DownloadedTrack? _local({required bool video}) =>
      widget.offline?.isVideo == video ? widget.offline : ref.read(downloadsProvider).find(s.id, video: video);

  @override
  void initState() {
    super.initState();
    if (_audioOnly) WidgetsBinding.instance.addPostFrameCallback((_) => _playAudio());
  }

  Future<void> _playAudio() async {
    final local = _local(video: false);
    final url = local?.path ?? s.audioUrl ?? (s.hasVideo ? s.videoUrl : null);
    if (url == null) return;
    Analytics.sermonPlay(s.id);
    await ref.read(audioPlayerServiceProvider).play(id: s.id, url: url, isFile: local != null, title: s.title, artist: s.speaker ?? 'Conacce TV', artworkUrl: s.thumbnailUrl);
  }

  Future<void> _download({required bool video}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(downloadsProvider.notifier).download(s, video: video);
      messenger.showSnackBar(SnackBar(content: Text('« ${s.title} » est disponible hors connexion.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.read(audioPlayerServiceProvider);
    final playing = ref.watch(audioPlayerStateProvider).valueOrNull?.playing ?? false;
    final isThis = audio.currentId == s.id;
    final downloads = ref.watch(downloadsProvider);
    final localVideo = _local(video: true);
    final videoSource = localVideo?.path ?? s.videoUrl;

    final player = !_audioOnly && videoSource != null
        ? HlsVideoPlayer(url: videoSource, isFile: localVideo != null, onStarted: () => Analytics.sermonPlay(s.id))
        : AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              NetCover(url: s.thumbnailUrl, radius: 0),
              const ColoredBox(color: Color(0x99080F43)),
              Center(
                child: GestureDetector(
                  onTap: () => !isThis ? _playAudio() : (playing ? audio.pause() : audio.resume()),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.sunGradient),
                    child: Icon(playing && isThis ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38, color: AppColors.navy),
                  ),
                ),
              ),
            ]),
          );

    Widget pill(IconData icon, String label, VoidCallback? onTap) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0x40FFFFFF)), shape: const StadiumBorder(), minimumSize: const Size(0, 44)),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );

    Widget downloadPill(bool video) {
      final done = downloads.find(s.id, video: video) != null;
      final progress = downloads.progress['${s.id}_${video ? 'v' : 'a'}'];
      if (done) return pill(Icons.download_done_rounded, 'Disponible hors connexion', null);
      if (progress != null) return pill(Icons.downloading_rounded, 'Téléchargement… ${(progress * 100).round()} %', null);
      return pill(Icons.download_rounded, video ? 'Télécharger la vidéo' : 'Télécharger l’audio', () => _download(video: video));
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.category.label)),
      extendBodyBehindAppBar: false,
      body: WaveBackground(
        child: ListView(
          children: [
            MaxWidth(
              maxWidth: 1000,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                player,
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, style: AppTheme.title(size: 18, weight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text([_sermonMeta(s), if (s.viewCount > 0) '${s.viewCount} vues'].where((e) => e.isNotEmpty).join(' · '),
                        style: const TextStyle(color: AppColors.mist, fontSize: 13)),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      if (s.hasVideo && s.hasAudio)
                        pill(_audioOnly ? Icons.videocam_rounded : Icons.headphones_rounded, _audioOnly ? 'Voir la vidéo' : 'Écouter en audio seul', () {
                          setState(() => _audioOnly = !_audioOnly);
                          if (_audioOnly) {
                            _playAudio();
                          } else if (isThis) {
                            audio.stop();
                          }
                        }),
                      pill(Icons.share_rounded, 'Partager', () => Share.share('« ${s.title} » — à revoir sur l’appli Conacce TV')),
                      if (DownloadsController.supported && s.isDownloadable && s.hasAudio) downloadPill(false),
                      if (DownloadsController.supported && s.isDownloadable && s.hasVideo && !(s.videoUrl ?? '').contains('.m3u8')) downloadPill(true),
                    ]),
                    if (s.description != null && s.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(s.description!, style: const TextStyle(color: AppColors.mist, height: 1.6)),
                    ],
                  ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
