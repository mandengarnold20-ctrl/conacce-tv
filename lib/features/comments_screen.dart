import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics.dart';
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
            const Text('Votre avis, votre témoignage, un encouragement : écrivez à Conacce TV.', style: TextStyle(color: AppColors.mist, fontSize: 13)),
            const SizedBox(height: 14),
            const _WallComposer(),
          ]),
        ),
        Expanded(
          child: comments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const _Empty('Connexion impossible pour le moment.'),
            data: (items) => items.isEmpty
                ? const _Empty('Soyez le premier à laisser un commentaire.')
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

class _WallComposer extends StatefulWidget {
  const _WallComposer();

  @override
  State<_WallComposer> createState() => _WallComposerState();
}

class _WallComposerState extends State<_WallComposer> {
  final _name = TextEditingController();
  final _body = TextEditingController();
  String? _country;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final saved = p.getString('comment_name');
      if (saved != null) _name.text = saved;
      setState(() => _country = p.getString('comment_country'));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final name = _name.text.trim();
    final body = _body.text.trim();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (name.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('Indiquez votre prénom.')));
      return;
    }
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await sendWallComment(name: name, body: body, countryCode: _country, visitorId: await Analytics.visitorId());
      final p = await SharedPreferences.getInstance();
      p.setString('comment_name', name);
      if (_country != null) p.setString('comment_country', _country!);
      _body.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      final wait = e.toString().contains('Patientez');
      messenger?.showSnackBar(SnackBar(content: Text(wait ? 'Patientez quelques secondes avant un nouveau message.' : 'Message non envoyé. Vérifiez votre connexion.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickCountry() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navyDeep,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CountrySheet(),
    );
    if (code != null) setState(() => _country = code);
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: const Color(0x330B1463),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.sunGold)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14),
            decoration: _deco('Votre prénom'),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _pickCountry,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0x330B1463), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x22FFFFFF))),
            alignment: Alignment.center,
            child: Text(
              _country == null ? 'Pays' : '${countryFlag(_country)}  ${countryName(_country) ?? _country}',
              style: TextStyle(color: _country == null ? AppColors.muted : Colors.white, fontSize: 13),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _body,
            maxLength: 1000,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(fontSize: 14),
            decoration: _deco('Écrivez votre commentaire'),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _sending ? null : _send,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(gradient: AppColors.sunGradient, shape: BoxShape.circle),
            child: _sending
                ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy))
                : const Icon(Icons.send_rounded, color: AppColors.navy, size: 20),
          ),
        ),
      ]),
    ]);
  }
}

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
