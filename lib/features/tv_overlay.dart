import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../core/theme/app_colors.dart';
import '../core/widgets/brand.dart';
import '../data/branding.dart';
import '../data/tv_schedule.dart';

// Polices de l'habillage : celles de la chaîne (dossier fonts/ du site) ou importées en régie.
// Chargées une seule fois, à la demande ; le navigateur les garde ensuite en mémoire.
final Set<String> _fontsLoaded = {};
final Set<String> _fontsLoading = {};
String _familyOf(BrandFont f) => 'conacce_font_${f.key.hashCode.abs()}';

Future<void> _loadFont(BrandFont f, VoidCallback done) async {
  final key = f.key;
  if (_fontsLoaded.contains(key) || _fontsLoading.contains(key)) return;
  _fontsLoading.add(key);
  try {
    final loader = FontLoader(_familyOf(f));
    var any = false;
    for (final file in f.files) {
      final r = await http.get(Uri.base.resolve(file));
      if (r.statusCode == 200) {
        loader.addFont(Future.value(ByteData.sublistView(r.bodyBytes)));
        any = true;
      }
    }
    if (any) {
      await loader.load();
      _fontsLoaded.add(key);
      done();
    }
  } catch (_) {
    // Police illisible : on garde la police par défaut.
  } finally {
    _fontsLoading.remove(key);
  }
}

/// Style de texte de l'habillage, dans la police [font] (sinon la police générale).
TextStyle brandStyle(Branding b,
    {BrandFont? font, required double size, FontWeight weight = FontWeight.w700, Color color = Colors.white}) {
  final f = font ?? b.font;
  if (_fontsLoaded.contains(f.key)) {
    return TextStyle(
      fontFamily: _familyOf(f),
      fontSize: size,
      fontWeight: weight,
      // Polices « variables » (une seule fichier pour toutes les graisses).
      fontVariations: [FontVariation('wght', (weight.index + 1) * 100.0)],
      color: color,
      height: 1.15,
    );
  }
  return GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color, height: 1.15);
}

/// Habillage dessiné par-dessus la TV : logo, bande artiste / titre, bandeau d'infos défilant.
class TvOverlay extends StatefulWidget {
  const TvOverlay({super.key, required this.branding, required this.now, this.slot});

  final Branding branding;
  final DateTime Function() now;

  /// Programme en cours (null pendant un direct : pas de bande artiste).
  final TvSlot? slot;

  @override
  State<TvOverlay> createState() => _TvOverlayState();
}

class _TvOverlayState extends State<TvOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureFonts(Branding b) {
    for (final f in {b.font.key: b.font, b.tickerFont.key: b.tickerFont, b.bandFont.key: b.bandFont}.values) {
      if (!_fontsLoaded.contains(f.key)) {
        _loadFont(f, () {
          if (mounted) setState(() {});
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.branding;
    _ensureFonts(b);
    final now = widget.now();
    final tickerText = b.tickerShow ? b.tickerAt(now) : '';

    // Bande artiste : à X s du début du clip, puis (si réglé) X s avant la fin.
    final slot = widget.slot;
    var bandOn = false;
    if (b.bandShow && slot != null && slot.program.hasBand) {
      final pos = now.difference(slot.start).inMilliseconds / 1000.0;
      final total = slot.program.duration.inSeconds.toDouble();
      bool inWindow(double a) => pos >= a && pos < a + b.bandDur;
      bandOn = inWindow(b.bandAt.toDouble()) ||
          (b.bandEnd > 0 && total > b.bandEnd + b.bandAt + b.bandDur && inWindow(total - b.bandEnd));
    }

    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 640.0;
        final h = c.maxHeight.isFinite ? c.maxHeight : w * 9 / 16;
        final k = (w / 640).clamp(0.5, 2.5).toDouble();
        final tickerH = tickerText.isEmpty ? 0.0 : (22 * k).clamp(16.0, 46.0).toDouble();
        final margin = 10 * k;
        final top = b.logoCorner.startsWith('h');
        final left = b.logoCorner.endsWith('g');
        final free = b.logoX != null && b.logoY != null;
        final logoW = w * 0.17 * b.logoSize / 100;

        // Position de la bande : bas ou haut, gauche / centre / droite, hauteur réglable.
        final bandTop = b.bandPos.startsWith('h');
        final hz = b.bandPos.length > 1 ? b.bandPos[1] : 'c';
        final shift = h * b.bandY / 100;
        return Stack(clipBehavior: Clip.hardEdge, children: [
          if (b.logoShow)
            Positioned(
              // Position libre réglée à la souris dans la régie, sinon un des quatre coins.
              top: free ? (b.logoY! * h).clamp(0.0, (h - 8).clamp(0.0, h)).toDouble() : top ? margin : null,
              bottom: free ? null : top ? null : margin + tickerH,
              left: free ? (b.logoX! * w).clamp(0.0, (w - logoW).clamp(0.0, w)).toDouble() : left ? margin : null,
              right: free ? null : left ? null : margin,
              child: Opacity(
                opacity: b.logoOpacity / 100,
                // Notre logo officiel, avec le reflet de lumière qui le traverse (comme dans l'appli).
                child: b.logoUrl != null
                    ? SizedBox(
                        width: w * 0.17 * b.logoSize / 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3 * k),
                          child: Image.network(b.logoUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => LogoShine(width: w * 0.17 * b.logoSize / 100, radius: 3 * k)),
                        ),
                      )
                    : LogoShine(width: w * 0.17 * b.logoSize / 100, radius: 3 * k),
              ),
            ),
          if (slot != null && slot.program.hasBand)
            Positioned(
              left: margin,
              right: margin,
              top: bandTop ? margin + shift : null,
              bottom: bandTop ? null : tickerH + 14 * k + shift,
              child: Align(
                alignment: hz == 'g'
                    ? Alignment.centerLeft
                    : hz == 'd'
                        ? Alignment.centerRight
                        : Alignment.center,
                child: _Band(
                  visible: bandOn,
                  fromTop: bandTop,
                  artist: (slot.program.artist ?? '').trim(),
                  song: (slot.program.song ?? '').trim(),
                  k: k,
                  maxWidth: w * b.bandWidth / 100,
                  branding: b,
                ),
              ),
            ),
          if (tickerText.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: tickerH,
              child: RepaintBoundary(
                  child: _Ticker(text: tickerText, speed: b.tickerSpeed, height: tickerH, branding: b)),
            ),
        ]);
      }),
    );
  }
}

/// Bande artiste : nom sur le dégradé (couleurs du logo par défaut), titre sur fond blanc.
/// Animation d'entrée et animation de sortie réglables séparément en régie.
class _Band extends StatefulWidget {
  const _Band({
    required this.visible,
    required this.fromTop,
    required this.artist,
    required this.song,
    required this.k,
    required this.maxWidth,
    required this.branding,
  });

  final bool visible;
  final bool fromTop;
  final String artist;
  final String song;
  final double k;
  final double maxWidth;
  final Branding branding;

  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> with SingleTickerProviderStateMixin {
  // Le dégradé ne bouge que pendant que la bande est à l'écran (rien à calculer le reste du temps).
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  /// Animation utilisée pour l'état caché : celle de sortie juste après la sortie,
  /// puis celle d'entrée (préparée en coulisse, invisible) pour le prochain passage.
  late String _hiddenStyle = widget.branding.bandAnim;
  Timer? _swap;

  void _syncFlow() {
    if (widget.visible && !_flow.isAnimating) {
      _flow.repeat(reverse: true);
    } else if (!widget.visible && _flow.isAnimating) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && !widget.visible) _flow.stop();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _syncFlow();
  }

  @override
  void didUpdateWidget(covariant _Band old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) {
      _syncFlow();
      _swap?.cancel();
      if (!widget.visible) {
        // Sortie : on part avec l'animation de sortie, puis on se prépare pour la prochaine entrée.
        _hiddenStyle = widget.branding.bandAnimOut;
        _swap = Timer(const Duration(milliseconds: 900), () {
          if (mounted && !widget.visible) setState(() => _hiddenStyle = widget.branding.bandAnim);
        });
      } else {
        _hiddenStyle = widget.branding.bandAnim;
      }
    } else if (!widget.visible && _swap == null) {
      _hiddenStyle = widget.branding.bandAnim;
    }
  }

  @override
  void dispose() {
    _swap?.cancel();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.branding;
    final k = widget.k * b.bandScale / 100;
    final font = b.bandFont;
    final card = ConstrainedBox(
      constraints: BoxConstraints(minWidth: (150 * k).clamp(0, widget.maxWidth).toDouble(), maxWidth: widget.maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5 * k),
          boxShadow: [BoxShadow(color: const Color(0x59000000), blurRadius: 14 * k, offset: Offset(0, 4 * k))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5 * k),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.artist.isNotEmpty)
              AnimatedBuilder(
                animation: _flow,
                builder: (context, child) {
                  final v = _flow.value;
                  final mid = Color.lerp(b.bandTopA, b.bandTopB, .5)!;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 - 2 * v, 0),
                        end: Alignment(3 - 2 * v, 0),
                        colors: [b.bandTopA, b.bandTopB, mid, b.bandTopA],
                      ),
                    ),
                    child: child,
                  );
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 5 * k),
                  child: Text(widget.artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: brandStyle(b, font: font, size: 14 * k, weight: FontWeight.w800, color: b.bandTopText)),
                ),
              ),
            if (widget.song.isNotEmpty)
              ColoredBox(
                color: b.bandBottomBg,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 3 * k),
                  child: Text(widget.song,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: brandStyle(b, font: font, size: 10.5 * k, weight: FontWeight.w600, color: b.bandBottomText)),
                ),
              ),
          ]),
        ),
      ),
    );
    final on = widget.visible;
    final style = on ? b.bandAnim : _hiddenStyle;
    final slideAway = Offset(0, widget.fromTop ? -1.6 : 1.6);
    final dur = Duration(milliseconds: style == 'open' ? 550 : 650);
    // Les trois effets sont toujours en place : seul l'effet choisi bouge (pas de saut d'image).
    return AnimatedSlide(
      offset: on || style != 'slide' ? Offset.zero : slideAway,
      duration: dur,
      curve: on ? Curves.easeOutCubic : Curves.easeInCubic,
      child: AnimatedScale(
        scale: on || style != 'open' ? 1 : 0.2,
        duration: dur,
        curve: on ? Curves.easeOutBack : Curves.easeInBack,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: Duration(milliseconds: style == 'fade' ? 700 : 400),
          child: card,
        ),
      ),
    );
  }
}

/// Bandeau d'infos défilant en bas de l'image.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.text, required this.speed, required this.height, required this.branding});

  final String text;
  final int speed;
  final double height;
  final Branding branding;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));
  double _cycle = 1;
  String? _key;

  Branding get _b => widget.branding;
  Color get _fg =>
      _b.tickerFg ?? switch (_b.tickerTheme) { 'blanc' => AppColors.navy, 'noir' => AppColors.sunYellow, _ => Colors.white };
  Color get _bg =>
      _b.tickerBg ??
      switch (_b.tickerTheme) { 'blanc' => Colors.white, 'noir' => const Color(0xD9000000), _ => const Color(0xEB0B1463) };

  TextStyle get _style => brandStyle(_b, font: _b.tickerFont, size: widget.height * 0.52, weight: FontWeight.w500, color: _fg);

  void _sync() {
    final tp = TextPainter(text: TextSpan(text: widget.text, style: _style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    final gap = widget.height * 3;
    final cycle = tp.width + gap;
    final pxPerSec = const [0.0, 30.0, 45.0, 65.0, 90.0, 125.0][widget.speed.clamp(1, 5).toInt()] * (widget.height / 22);
    final key = '${cycle.round()}|${pxPerSec.round()}';
    if (key == _key) return;
    _key = key;
    _cycle = cycle;
    final ms = (cycle / pxPerSec * 1000).round().clamp(2000, 900000).toInt();
    _c.duration = Duration(milliseconds: ms);
    _c
      ..reset()
      ..repeat();
  }

  @override
  void initState() {
    super.initState();
    _lastSig = _sig(widget);
    _sync();
  }

  static String _sig(_Ticker t) {
    final f = t.branding.tickerFont;
    return '${t.text}|${t.speed}|${t.height}|${f.key}|${_fontsLoaded.contains(f.key)}';
  }

  String? _lastSig;

  @override
  void didUpdateWidget(covariant _Ticker old) {
    super.didUpdateWidget(old);
    // Texte, vitesse, taille ou police changés : on remesure (la police peut finir de charger après).
    final sig = _sig(widget);
    if (sig != _lastSig) {
      _lastSig = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_sync);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final style = _style;
    final gap = h * 3;
    final copies = ((MediaQuery.sizeOf(context).width / _cycle).ceil() + 2).clamp(2, 40).toInt();
    return ColoredBox(
      color: _bg,
      child: Row(children: [
        Container(
          height: h,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: h * 0.45),
          decoration: const BoxDecoration(gradient: AppColors.sunGradient),
          child: Text('INFO', style: brandStyle(_b, font: _b.tickerFont, size: h * 0.42, weight: FontWeight.w800, color: AppColors.navy)),
        ),
        Expanded(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: Transform.translate(offset: Offset(-_c.value * _cycle, 0), child: child),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < copies; i++) ...[
                  Text(widget.text, style: style, maxLines: 1, softWrap: false),
                  SizedBox(width: gap),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
