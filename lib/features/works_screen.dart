import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/analytics.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/models.dart';
import '../data/providers.dart';

void openWork(BuildContext context, Work w) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkDetailScreen(work: w)));
}

/// Lecture d'une œuvre : dans l'appli sur téléphone, dans un onglet sur le web.
Future<void> readWork(BuildContext context, Work w) async {
  Analytics.workRead(w.id);
  if (kIsWeb) {
    await launchUrl(Uri.parse(w.pdfUrl!), mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfReaderScreen(work: w)));
}

/// Onglet Œuvres d'Or : les écrits de l'homme de Dieu.
class WorksScreen extends ConsumerWidget {
  const WorksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final works = ref.watch(worksProvider);
    final name = ref.watch(settingsProvider).valueOrNull?.manOfGodName;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(worksProvider.future),
      child: works.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Connexion impossible pour le moment.', style: TextStyle(color: AppColors.muted))),
        data: (list) {
          final featured = list.where((w) => w.isFeatured).firstOrNull ?? list.firstOrNull;
          return LayoutBuilder(builder: (context, c) {
            final cols = (c.maxWidth / 150).floor().clamp(3, 8);
            return CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: MaxWidth(
                  maxWidth: 1000,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Œuvres d’Or', style: AppTheme.title(size: 22, weight: FontWeight.w800)),
                      if (name != null) ...[
                        const SizedBox(height: 2),
                        Text('Les écrits de $name', style: const TextStyle(color: AppColors.mist, fontSize: 13)),
                      ],
                      const SizedBox(height: 16),
                      if (featured != null) _Featured(work: featured),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Les Œuvres d’Or arrivent bientôt.', style: TextStyle(color: AppColors.muted))),
                        ),
                      if (list.length > 1) ...[
                        const SizedBox(height: 18),
                        Text('Toutes les œuvres', style: AppTheme.title(size: 16, weight: FontWeight.w800)),
                        const SizedBox(height: 12),
                      ],
                    ]),
                  ),
                ),
              ),
              if (list.length > 1)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 14, mainAxisSpacing: 16, childAspectRatio: .52),
                    delegate: SliverChildBuilderDelegate((context, i) => WorkCover(work: list[i]), childCount: list.length),
                  ),
                ),
            ]);
          });
        },
      ),
    );
  }
}

/// Couverture + titre (grille et accueil).
class WorkCover extends StatelessWidget {
  const WorkCover({super.key, required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openWork(context, work),
      borderRadius: BorderRadius.circular(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: NetCover(url: work.coverUrl, radius: 8, icon: Icons.menu_book_rounded, fallback: AppColors.sunGradient),
        ),
        const SizedBox(height: 6),
        Text(work.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25)),
      ]),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    return NavyCard(
      onTap: () => openWork(context, work),
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(6, 10))]),
              child: NetCover(url: work.coverUrl, radius: 8, icon: Icons.menu_book_rounded, fallback: AppColors.sunGradient),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0x2EF9CA22), borderRadius: BorderRadius.circular(10)),
              child: const Text('À la une', style: TextStyle(color: AppColors.sunYellow, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text(work.title, style: AppTheme.title(size: 15)),
            if (work.subtitle != null) Text(work.subtitle!, style: const TextStyle(color: AppColors.mist, fontSize: 12)),
            const SizedBox(height: 4),
            Text([if (work.pages != null) '${work.pages} pages', if (work.year != null) '${work.year}'].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 12),
            _WorkActions(work: work, compact: true),
          ]),
        ),
      ]),
    );
  }
}

class _WorkActions extends StatelessWidget {
  const _WorkActions({required this.work, this.compact = false});

  final Work work;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      if (work.canRead) SunButton(label: 'Lire maintenant', icon: Icons.auto_stories_rounded, height: compact ? 42 : 48, onPressed: () => readWork(context, work)),
      if (!work.isFree && (work.buyUrl?.isNotEmpty ?? false))
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0x40FFFFFF)), shape: const StadiumBorder(), minimumSize: Size(0, compact ? 42 : 48)),
          onPressed: () => launchUrl(Uri.parse(work.buyUrl!), mode: LaunchMode.externalApplication),
          child: Text('Obtenir${work.priceLabel == null ? '' : ' · ${work.priceLabel}'}'),
        ),
    ]);
  }
}

/// Fiche d'une œuvre.
class WorkDetailScreen extends StatelessWidget {
  const WorkDetailScreen({super.key, required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Œuvres d’Or')),
      body: WaveBackground(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
          MaxWidth(
            maxWidth: 640,
            child: Column(children: [
              SizedBox(
                width: 180,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(8, 14))]),
                    child: NetCover(url: work.coverUrl, radius: 10, icon: Icons.menu_book_rounded, fallback: AppColors.sunGradient),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(work.title, textAlign: TextAlign.center, style: AppTheme.title(size: 20, weight: FontWeight.w800)),
              if (work.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(work.subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mist)),
              ],
              const SizedBox(height: 6),
              Text(
                [if (work.pages != null) '${work.pages} pages', if (work.year != null) '${work.year}', work.isFree ? 'Gratuit' : (work.priceLabel ?? '')].where((e) => e.isNotEmpty).join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _WorkActions(work: work),
              if (work.description != null) ...[
                const SizedBox(height: 22),
                Text(work.description!, style: const TextStyle(color: AppColors.mist, height: 1.6)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Lecteur PDF dans l'appli (Android / iPhone) : pages, zoom au doigt.
class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({super.key, required this.work});

  final Work work;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  PdfControllerPinch? _controller;
  Object? _error;
  int _page = 1, _pages = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse(widget.work.pdfUrl!));
      if (res.statusCode != 200) throw Exception('PDF indisponible (${res.statusCode})');
      if (!mounted) return;
      setState(() => _controller = PdfControllerPinch(document: PdfDocument.openData(res.bodyBytes)));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        title: Text(widget.work.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_pages > 0)
            Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('$_page / $_pages', style: const TextStyle(color: AppColors.mist)))),
        ],
      ),
      body: _error != null
          ? const Center(child: Text('Impossible d’ouvrir ce livre. Vérifiez votre connexion.', style: TextStyle(color: AppColors.muted)))
          : _controller == null
              ? const Center(child: CircularProgressIndicator())
              : PdfViewPinch(
                  controller: _controller!,
                  onDocumentLoaded: (doc) => setState(() => _pages = doc.pagesCount),
                  onPageChanged: (p) => setState(() => _page = p),
                ),
    );
  }
}
