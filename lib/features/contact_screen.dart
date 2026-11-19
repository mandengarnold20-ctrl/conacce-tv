import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/analytics.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/countries.dart';
import '../data/models.dart';
import '../data/providers.dart';

void openContact(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactScreen()));
}

/// Contact : site et e-mail de la CONACCE, puis messagerie (avec le pays de chacun).
class ContactScreen extends ConsumerWidget {
  const ContactScreen({super.key, this.asTab = false});

  /// Affiché comme onglet du menu du bas (sans barre de titre).
  final bool asTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final site = settings.website;
    final siteLabel = Uri.tryParse(site)?.host.replaceFirst('www.', '') ?? site;
    final email = settings.email;

    final content = ListView(
          padding: EdgeInsets.fromLTRB(20, asTab ? MediaQuery.paddingOf(context).top + 18 : 12, 20, asTab ? 120 : 40),
          children: [
            MaxWidth(
              maxWidth: 640,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Restons en contact', style: AppTheme.title(size: 22, weight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Où que vous soyez dans le monde, écrivez-nous : nous lisons chaque message.',
                    style: TextStyle(color: AppColors.mist, height: 1.5)),
                const SizedBox(height: 18),
                _LinkCard(
                  icon: Icons.language_rounded,
                  title: 'Site de la CONACCE',
                  value: siteLabel,
                  onTap: () => launchUrl(Uri.parse(site), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 10),
                _LinkCard(
                  icon: Icons.mail_rounded,
                  title: 'E-mail',
                  value: email,
                  onTap: () => launchUrl(Uri(scheme: 'mailto', path: email)),
                ),
                if (settings.whatsappUrl != null) ...[
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.chat_rounded,
                    title: 'WhatsApp',
                    value: 'Écrire sur WhatsApp',
                    onTap: () => launchUrl(Uri.parse(settings.whatsappUrl!), mode: LaunchMode.externalApplication),
                  ),
                ],
                if (settings.facebookUrl != null) ...[
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.facebook_rounded,
                    title: 'Facebook',
                    value: 'Notre page Facebook',
                    onTap: () => launchUrl(Uri.parse(settings.facebookUrl!), mode: LaunchMode.externalApplication),
                  ),
                ],
                if (settings.youtubeUrl != null) ...[
                  const SizedBox(height: 10),
                  _LinkCard(
                    icon: Icons.smart_display_rounded,
                    title: 'YouTube',
                    value: 'Notre chaîne YouTube',
                    onTap: () => launchUrl(Uri.parse(settings.youtubeUrl!), mode: LaunchMode.externalApplication),
                  ),
                ],
                const SizedBox(height: 28),
                Text('Messagerie', style: AppTheme.title(size: 18, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Prière, témoignage, question… Indiquez votre pays : votre drapeau apparaîtra avec votre message.',
                    style: TextStyle(color: AppColors.mist, fontSize: 13, height: 1.5)),
                const SizedBox(height: 14),
                const _MessageForm(),
              ]),
            ),
          ],
        );
    if (asTab) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: WaveBackground(child: content),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.icon, required this.title, required this.value, required this.onTap});

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NavyCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: AppColors.navy),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.mist, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.title(size: 14).copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.sunGold)),
          ]),
        ),
        const Icon(Icons.open_in_new_rounded, color: AppColors.muted, size: 18),
      ]),
    );
  }
}

class _MessageForm extends StatefulWidget {
  const _MessageForm();

  @override
  State<_MessageForm> createState() => _MessageFormState();
}

class _MessageFormState extends State<_MessageForm> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _body = TextEditingController();
  String? _country;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Pays proposé d'après la langue / région du téléphone (modifiable).
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase();
    if (countryName(region) != null) _country = region;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_name.text.trim().isEmpty || _body.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Indiquez votre nom et votre message.')));
      return;
    }
    if (_country == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Choisissez votre pays.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await sendMessage(
        name: _name.text,
        body: _body.text,
        visitorId: await Analytics.visitorId(),
        countryCode: _country,
        countryName: countryName(_country),
        email: _email.text,
        phone: _phone.text,
      );
      _body.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Merci ! Votre message a bien été envoyé à la CONACCE.')));
    } catch (e) {
      final wait = e.toString().contains('Patientez');
      messenger.showSnackBar(SnackBar(content: Text(wait ? 'Patientez quelques secondes avant un nouveau message.' : 'Message non envoyé. Vérifiez votre connexion.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _deco(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, color: AppColors.muted, size: 20),
        filled: true,
        fillColor: const Color(0x330B1463),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.sunGold)),
      );

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.navyDeep,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CountryPicker(),
    );
    if (picked != null) setState(() => _country = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: _deco('Votre nom', icon: Icons.person_rounded).copyWith(counterText: '')),
      const SizedBox(height: 10),
      InkWell(
        onTap: _pickCountry,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: _deco('Votre pays'),
          child: Row(children: [
            Text(countryFlag(_country), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text(countryName(_country) ?? 'Choisir un pays', style: TextStyle(color: _country == null ? AppColors.muted : Colors.white))),
            const Icon(Icons.expand_more_rounded, color: AppColors.muted),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      TextField(controller: _email, keyboardType: TextInputType.emailAddress, maxLength: 120, decoration: _deco('E-mail (facultatif)', icon: Icons.alternate_email_rounded).copyWith(counterText: '')),
      const SizedBox(height: 10),
      TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 30, decoration: _deco('Téléphone / WhatsApp (facultatif)', icon: Icons.phone_rounded).copyWith(counterText: '')),
      const SizedBox(height: 10),
      TextField(controller: _body, minLines: 4, maxLines: 8, maxLength: 2000, decoration: _deco('Votre message').copyWith(alignLabelWithHint: true)),
      const SizedBox(height: 14),
      SunButton(label: _sending ? 'Envoi…' : 'Envoyer mon message', icon: Icons.send_rounded, onPressed: _sending ? null : _send),
    ]);
  }
}

/// Liste des pays avec drapeau et recherche.
class _CountryPicker extends StatefulWidget {
  const _CountryPicker();

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  String _q = '';

  String _norm(String s) => s
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
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Rechercher un pays…', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => ListTile(
                leading: Text(countryFlag(list[i].$1), style: const TextStyle(fontSize: 24)),
                title: Text(list[i].$2),
                onTap: () => Navigator.of(context).pop(list[i].$1),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
