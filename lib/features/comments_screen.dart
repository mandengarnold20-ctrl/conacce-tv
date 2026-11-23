import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/responsive.dart';
import '../data/countries.dart';
import '../data/models.dart';
import '../data/providers.dart';

/// Onglet « Commentaires » : un mur où chacun laisse un message à la chaîne
/// (avis, témoignage, encouragement), avec son prénom et son pays.
class CommentsScreen extends ConsumerWidget {
  const CommentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(wallCommentsProvider);
    return MaxWidth(
      maxWidth: 800,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Commentaires', style: AppTheme.title(size: 26, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Les commentaires laissés sur Conacce TV, avec le pays de chacun.', style: TextStyle(color: AppColors.mist, fontSize: 13)),
          ]),
        ),
        Expanded(
          child: comments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const _Empty('Connexion impossible pour le moment.'),
            data: (items) => items.isEmpty
                ? const _Empty('Aucun commentaire pour le moment.\nÉcrivez sous la TV : votre message apparaîtra ici.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _Card(comment: items[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Choisir son pays (liste avec drapeaux et recherche).
Future<String?> pickCountry(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navyDeep,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CountrySheet(),
    );

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final list = kCountries.where((c) => _q.isEmpty || _norm(c.$2).contains(_norm(_q))).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              hintText: 'Rechercher un pays',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0x330B1463),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              leading: Text(countryFlag(list[i].$1), style: const TextStyle(fontSize: 22)),
              title: Text(list[i].$2),
              onTap: () => Navigator.of(context).pop(list[i].$1),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.comment});

  final WallComment comment;

  @override
  Widget build(BuildContext context) {
    final c = comment.countryCode;
    final when = DateFormat("d MMM 'à' HH:mm", 'fr_FR').format(comment.createdAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (c != null) ...[Text(countryFlag(c), style: const TextStyle(fontSize: 15)), const SizedBox(width: 6)],
          Expanded(
            child: Text(comment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 13, color: AppColors.sunYellow)),
          ),
          Text(when, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
        if (c != null && countryName(c) != null) ...[
          const SizedBox(height: 1),
          Text(countryName(c)!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
        const SizedBox(height: 6),
        Text(comment.body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
      ]),
    );
  }
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
