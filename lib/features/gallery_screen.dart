import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';

/// Galerie photo : deux albums, Conacce Chaplains et CIU.
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  static const _albums = [('conacce', 'Conacce Chaplains'), ('ciu', 'CIU')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(galleryAlbumProvider);
    final photos = ref.watch(galleryProvider(album));
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 5 : width >= 700 ? 4 : 3;

    return MaxWidth(
      maxWidth: 1100,
      child: RefreshIndicator(
        onRefresh: () => ref.refresh(galleryProvider(album).future),
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Galerie photo', style: AppTheme.title(size: 24, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Nos moments, nos actions et nos rencontres en images.', style: TextStyle(color: AppColors.mist, fontSize: 13)),
                const SizedBox(height: 16),
                Row(children: [
                  for (final (i, (key, label)) in _albums.indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: _AlbumTab(
                        label: label,
                        selected: album == key,
                        onTap: () => ref.read(galleryAlbumProvider.notifier).state = key,
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
              ]),
            ),
          ),
          ...photos.when<List<Widget>>(
            loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
            error: (_, __) => [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Connexion impossible pour le moment.'))],
            data: (items) => items.isEmpty
                ? [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Les photos arrivent bientôt.'))]
                : [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 6, crossAxisSpacing: 6),
                        itemCount: items.length,
                        itemBuilder: (context, i) => GestureDetector(
                          onTap: () => Navigator.of(context).push(PageRouteBuilder(
                            opaque: false,
                            barrierColor: Colors.black,
                            pageBuilder: (_, __, ___) => _PhotoViewer(items: items, initial: i),
                            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
                          )),
                          child: Hero(tag: 'photo-${items[i].id}', child: NetCover(url: items[i].imageUrl, radius: 8, icon: Icons.photo_rounded)),
                        ),
                      ),
                    ),
                  ],
          ),
        ]),
      ),
    );
  }
}

class _AlbumTab extends StatelessWidget {
  const _AlbumTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 44,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.sunGradient : AppColors.cardGradient,
            borderRadius: BorderRadius.circular(12),
            border: selected ? null : Border.all(color: const Color(0x22FFFFFF)),
          ),
          alignment: Alignment.center,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 13, color: selected ? AppColors.navy : Colors.white)),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))),
      );
}

/// Ouvre une photo en grand (on glisse pour passer aux suivantes).
void openPhotoViewer(BuildContext context, List<GalleryPhoto> items, int initial) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _PhotoViewer(items: items, initial: initial),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

/// Photo en grand : on glisse pour passer à la suivante, on pince pour zoomer.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.items, required this.initial});

  final List<GalleryPhoto> items;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Lance le téléchargement : le fichier est enregistré dans le téléphone
  /// (dossier Téléchargements, ou « Fichiers » sur iPhone).
  Future<void> _download(GalleryPhoto photo) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var url = photo.imageUrl;
    // Photos de la galerie (stockage Supabase) : on demande le fichier « à télécharger ».
    if (url.contains('/storage/v1/object/public/')) {
      final name = 'conacce-${photo.album}-${photo.id.substring(0, 8)}.jpg';
      url = '$url${url.contains('?') ? '&' : '?'}download=$name';
    }
    final ok = await launchUrl(
      Uri.parse(url),
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    messenger?.showSnackBar(SnackBar(content: Text(ok ? 'Téléchargement de la photo lancé.' : 'Téléchargement impossible pour le moment.')));
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: Hero(
                tag: 'photo-${widget.items[i].id}',
                child: CachedNetworkImage(
                  imageUrl: widget.items[i].imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: AppColors.sunYellow)),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.muted, size: 48),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Text('${_index + 1} / ${widget.items.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              // Télécharger la photo dans le téléphone
              TextButton.icon(
                onPressed: () => _download(photo),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  backgroundColor: AppColors.sunYellow,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Télécharger', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
        if (photo.caption != null && photo.caption!.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
                  child: Text(photo.caption!, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
