import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/analytics.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/models.dart';
import '../data/providers.dart';

/// Fil des messages du jour, entre la phrase d'accueil et la zone pour écrire.
/// Le plus récent est en bas, juste au-dessus de la zone pour écrire ; les plus anciens
/// remontent et s'effacent en passant sous la phrase d'accueil.
class LiveCommentsFeed extends ConsumerWidget {
  const LiveCommentsFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(liveCommentsProvider).valueOrNull ?? const <LiveComment>[];
    if (comments.isEmpty) {
      return const Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 0, 20, 10),
          child: Text('Soyez le premier à laisser un commentaire.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ),
      );
    }
    // Fondu en haut : l'espace invisible sous la phrase d'accueil.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black],
        stops: [0, .22],
      ).createShader(r),
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
        itemCount: comments.length,
        itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(top: 6), child: _Bubble(comment: comments[i])),
      ),
    );
  }
}

/// Une phrase : début, partie soulignée, fin.
typedef _Slogan = (String, String, String);

/// Les phrases changent chaque minute ; le trait jaune-orange du logo se dessine sous la partie clé.
const List<_Slogan> _slogans = [
  ('Vous regardez Conacce TV, désormais ', 'partout avec vous', ' à travers le monde !'),
  ('Conacce TV, ', 'le meilleur', ' chez vous !'),
  ('Conacce TV, nos ', 'actions humanitaires', ' à travers le monde !'),
];

class WelcomeSlogan extends StatefulWidget {
  const WelcomeSlogan({super.key});

  @override
  State<WelcomeSlogan> createState() => _WelcomeSloganState();
}

class _WelcomeSloganState extends State<WelcomeSlogan> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _slogans.length);
      // Le trait se redessine une fois la nouvelle phrase apparue.
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _c.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width < 420 ? 23.0 : 30.0;
    final style = AppTheme.title(size: size, weight: FontWeight.w800).copyWith(height: 1.35);
    // Le texte du soulignement : animé pour la phrase affichée, fixe pour les phrases de mesure.
    InlineSpan span(_Slogan sl, {required bool animated}) {
      final (start, mark, end) = sl;
      final word = Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(mark, style: style));
      return TextSpan(style: style, children: [
        TextSpan(text: start),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: animated
              ? AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => CustomPaint(
                    foregroundPainter: _Swoosh(Curves.easeInOutCubic.transform(_c.value)),
                    child: child,
                  ),
                  child: word,
                )
              : word,
        ),
        TextSpan(text: end),
      ]);
    }

    // La zone garde toujours la hauteur de la phrase la plus longue :
    // quand la phrase change, la zone de commentaire en dessous ne bouge pas.
    return Stack(children: [
      for (final sl in _slogans)
        SizedBox(
          width: double.infinity,
          child: Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Text.rich(span(sl, animated: false)),
          ),
        ),
      Positioned.fill(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
          child: Align(
            key: ValueKey(_index),
            alignment: Alignment.topLeft,
            child: Text.rich(span(_slogans[_index], animated: true)),
          ),
        ),
      ),
    ]);
  }
}

/// Trait courbe dessiné à la main, au dégradé du soleil du logo.
class _Swoosh extends CustomPainter {
  _Swoosh(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width, y = size.height - 2;
    final path = Path()
      ..moveTo(w * .01, y - 1)
      ..quadraticBezierTo(w * .35, y + 4, w * .62, y)
      ..quadraticBezierTo(w * .85, y - 3, w * .99, y + 1);
    final metric = path.computeMetrics().first;
    final part = metric.extractPath(0, metric.length * progress);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(Offset(0, y), Offset(w, y), const [
        AppColors.sunYellow,
        AppColors.sunGold,
        AppColors.sunMid,
        AppColors.sunDeep,
      ], const [0, .35, .7, 1]);
    canvas.drawPath(part, paint);
  }

  @override
  bool shouldRepaint(_Swoosh old) => old.progress != progress;
}

/// Zone pour écrire un message (le prénom est mémorisé sur l'appareil).
class LiveComposer extends StatefulWidget {
  const LiveComposer({super.key});

  @override
  State<LiveComposer> createState() => _ComposerState();
}

class _ComposerState extends State<LiveComposer> {
  final _name = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString('comment_name');
      if (saved != null && mounted) _name.text = saved;
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
      await sendLiveComment(name: name, body: body, visitorId: await Analytics.visitorId());
      (await SharedPreferences.getInstance()).setString('comment_name', name);
      _body.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      final wait = e.toString().contains('Patientez');
      messenger?.showSnackBar(SnackBar(content: Text(wait ? 'Patientez quelques secondes avant un nouveau message.' : 'Message non envoyé. Vérifiez votre connexion.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: const Color(0x330B1463),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0x22FFFFFF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.sunGold)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _name,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 14),
        decoration: _deco('Votre prénom').copyWith(counterText: ''),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _body,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(fontSize: 14),
            decoration: _deco('Laissez votre commentaire').copyWith(counterText: ''),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.comment});

  final LiveComment comment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(comment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.title(size: 12, color: AppColors.sunYellow)),
          ),
          Text(DateFormat('HH:mm').format(comment.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 3),
        Text(comment.body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
      ]),
    );
  }
}
