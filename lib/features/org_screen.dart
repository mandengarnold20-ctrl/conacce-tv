import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/countries.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'gallery_screen.dart';
import 'sermons_screen.dart';

/// Pays choisi dans CCA / CIU (null = tous les pays, '' = International).
final _countryProvider = StateProvider.family<String?, String>((ref, org) => null);

/// Vidéos ou galerie affichée dans CCA / CIU.
final _orgViewProvider = StateProvider.family<int, String>((ref, org) => 0);

/// Onglets CCA (Conacce Chaplains Afrique) et CIU (Conacce International University) :
/// vidéos et galerie photo, rangées par pays avec leur drapeau.
class OrgScreen extends ConsumerWidget {
  const OrgScreen.cca({super.key})
      : org = 'conacce',
        title = 'CCA',
        subtitle = 'Vidéos et photos de la Conacce Chaplains, pays par pays.';

  const OrgScreen.ciu({super.key})
      : org = 'ciu',
        title = 'CIU',
        subtitle = 'Conacce International University : vidéos et photos, pays par pays.';

  /// « conacce » ou « ciu » (rubrique des vidéos, album des photos).
  final String org;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_orgViewProvider(org));
    // La régie choisit d'afficher ou non les pays ; sans pays, tout s'affiche ensemble.
    final settings = ref.watch(settingsProvider).valueOrNull;
    final showCountries = org == 'ciu' ? (settings?.showCountriesCiu ?? true) : (settings?.showCountriesCca ?? true);
    final country = showCountries ? ref.watch(_countryProvider(org)) : null;
    final videos = ref.watch(sermonsProvider((org, null)));
    final photos = ref.watch(galleryProvider(org));

    // Pays qui ont du contenu (vidéos ou photos) ; sans pays = International.
    final counts = <String, int>{};
    for (final v in videos.valueOrNull ?? const <Sermon>[]) {
      counts[v.country ?? ''] = (counts[v.country ?? ''] ?? 0) + 1;
    }
    for (final p in photos.valueOrNull ?? const <GalleryPhoto>[]) {
      counts[p.country ?? ''] = (counts[p.country ?? ''] ?? 0) + 1;
    }
    final codes = counts.keys.where((c) => c.isNotEmpty).toList()
      ..sort((a, b) => (countryName(a) ?? a).compareTo(countryName(b) ?? b));
    final hasIntl = counts.containsKey('');
    bool keep(String? c) => country == null || (c ?? '') == country;

    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 5 : width >= 700 ? 4 : 3;

    Widget countryChip(String? code) {
      final selected = country == code;
      final label = code == null ? 'Tous les pays' : code.isEmpty ? 'International' : (countryName(code) ?? code);
      final flag = code == null ? '' : code.isEmpty ? '🌍' : countryFlag(code);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: flag.isEmpty ? null : Text(flag, style: const TextStyle(fontSize: 16)),
          label: Text(label),
          selected: selected,
          onSelected: (_) => ref.read(_countryProvider(org).notifier).state = code,
          showCheckmark: false,
          labelStyle: TextStyle(color: selected ? AppColors.navy : Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          selectedColor: AppColors.sunYellow,
          backgroundColor: const Color(0x660B1463),
          side: BorderSide(color: selected ? Colors.transparent : const Color(0x33FFFFFF)),
          shape: const StadiumBorder(),
        ),
      );
    }

    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTheme.title(size: 26, weight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: AppColors.mist, fontSize: 13)),
      const SizedBox(height: 16),
      Row(children: [
        for (final (i, label) in ['Vidéos', 'Galerie'].indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _Tab(label: label, selected: view == i, onTap: () => ref.read(_orgViewProvider(org).notifier).state = i)),
        ],
      ]),
      const SizedBox(height: 12),
      if (showCountries && (codes.isNotEmpty || hasIntl))
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            countryChip(null),
            for (final c in codes) countryChip(c),
            if (hasIntl) countryChip(''),
          ]),
        ),
      const SizedBox(height: 8),
    ]);

    List<Widget> body;
    if (view == 0) {
      body = videos.when(
        loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
        error: (_, __) => [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Connexion impossible pour le moment.'))],
        data: (all) {
          final items = all.where((v) => keep(v.country)).toList();
          if (items.isEmpty) return [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Les vidéos arrivent bientôt.'))];
          return [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.builder(itemCount: items.length, itemBuilder: (_, i) => SermonTile(sermon: items[i])),
            ),
          ];
        },
      );
    } else {
      body = photos.when(
        loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
        error: (_, __) => [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Connexion impossible pour le moment.'))],
        data: (all) {
          final items = all.where((p) => keep(p.country)).toList();
          if (items.isEmpty) return [const SliverFillRemaining(hasScrollBody: false, child: _Empty('Les photos arrivent bientôt.'))];
          return [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 6, crossAxisSpacing: 6),
                itemCount: items.length,
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => openPhotoViewer(context, items, i),
                  child: Hero(tag: 'photo-${items[i].id}', child: NetCover(url: items[i].imageUrl, radius: 8, icon: Icons.photo_rounded)),
                ),
              ),
            ),
          ];
        },
      );
    }

    return MaxWidth(
      maxWidth: 1100,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sermonsProvider((org, null)));
          ref.invalidate(galleryProvider(org));
          await ref.read(galleryProvider(org).future).catchError((_) => <GalleryPhoto>[]);
        },
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 4),
            sliver: SliverToBoxAdapter(child: header),
          ),
          ...body,
        ]),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.selected, required this.onTap});

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
          child: Text(label, style: AppTheme.title(size: 13, color: selected ? AppColors.navy : Colors.white)),
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
