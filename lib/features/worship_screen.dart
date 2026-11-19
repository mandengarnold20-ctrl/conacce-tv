import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/responsive.dart';
import '../data/providers.dart';
import 'downloads.dart';
import 'sermons_screen.dart';

/// Louange et adoration : chants publiés comme les vidéos (lien YouTube / Facebook ou fichier),
/// à écouter en ligne ou à télécharger pour l'écoute hors connexion.
class WorshipScreen extends ConsumerStatefulWidget {
  const WorshipScreen({super.key});

  @override
  ConsumerState<WorshipScreen> createState() => _WorshipScreenState();
}

class _WorshipScreenState extends ConsumerState<WorshipScreen> {
  bool _offline = false;
  /// « louange » ou « adoration » : deux rubriques bien séparées.
  String _section = 'louange';

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(sermonsProvider((_section, null)));
    final downloads = ref.watch(downloadsProvider).items.where((t) => t.item.section == _section).toList();
    final label = _section == 'louange' ? 'louange' : 'adoration';

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

    Widget message(String text) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          ),
        );

    final Widget list = _offline
        ? (downloads.isEmpty
            ? message('Aucun chant de $label téléchargé.\nOuvrez un chant puis touchez « Télécharger ».')
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                children: [for (final t in downloads) SermonTile(sermon: t.item, offline: t)],
              ))
        : songs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => message('Connexion impossible pour le moment.'),
            data: (items) => items.isEmpty
                ? message('Les chants de $label arrivent bientôt.')
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(sermonsProvider((_section, null)).future),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                      itemCount: items.length,
                      itemBuilder: (context, i) => SermonTile(sermon: items[i]),
                    ),
                  ),
          );

    return MaxWidth(
      maxWidth: 900,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Louange & adoration', style: AppTheme.title(size: 24, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Chants à écouter en ligne ou à télécharger.', style: TextStyle(color: AppColors.mist, fontSize: 13)),
            const SizedBox(height: 14),
            // Deux rubriques séparées : Louange | Adoration
            Row(children: [
              Expanded(child: _Tab(label: 'Louange', selected: _section == 'louange', onTap: () => setState(() => _section = 'louange'))),
              const SizedBox(width: 10),
              Expanded(child: _Tab(label: 'Adoration', selected: _section == 'adoration', onTap: () => setState(() => _section = 'adoration'))),
            ]),
          ]),
        ),
        if (DownloadsController.supported)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 10, 12, 4),
              children: [
                chip('Tous les chants', !_offline, () => setState(() => _offline = false)),
                chip('Téléchargés', _offline, () => setState(() => _offline = true)),
              ],
            ),
          )
        else
          const SizedBox(height: 10),
        Expanded(child: list),
      ]),
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
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.sunGradient : AppColors.cardGradient,
            borderRadius: BorderRadius.circular(12),
            border: selected ? null : Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Text(label, style: AppTheme.title(size: 13, color: selected ? AppColors.navy : Colors.white)),
        ),
      );
}
