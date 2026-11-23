import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../core/theme/app_colors.dart';
import '../core/widgets/brand.dart';
import '../data/branding.dart';
import '../data/tv_schedule.dart';

// Polices importées depuis la régie (fichier .ttf / .otf / .woff2), chargées une seule fois.
final Set<String> _fontsLoaded = {};
final Set<String> _fontsLoading = {};
String _familyOf(String url) => 'conacce_font_${url.hashCode.abs()}';

Future<void> _loadFont(String url, VoidCallback done) async {
  if (_fontsLoaded.contains(url) || _fontsLoading.contains(url)) return;
  _fontsLoading.add(url);
  try {
    final r = await http.get(Uri.parse(url));
    if (r.statusCode == 200) {
      final loader = FontLoader(_familyOf(url))..addFont(Future.value(ByteData.sublistView(r.bodyBytes)));
      await loader.load();
      _fontsLoaded.add(url);
      done();
    }
  } catch (_) {
    // Police illisible : on garde la police par défaut.
  }
}

/// Style de texte de l'habillage, dans la police choisie en régie.
TextStyle brandStyle(Branding b, {required double size, FontWeight weight = FontWeight.w700, Color color = Colors.white}) {
  final url = b.fontUrl;
  if (url != null && _fontsLoaded.contains(url)) {
    return TextStyle(fontFamily: _familyOf(url), fontSize: size, fontWeight: weight, color: color, height: 1.15);
  }
  try {
    return GoogleFonts.getFont(b.fontName, fontSize: size, fontWeight: weight, color: color, height: 1.15);
  } catch (_) {
    return GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color, height: 1.15);
  }
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

  @override
  Widget build(BuildContext context) {
    final b = widget.branding;
    final url = b.fontUrl;
    if (url != null && !_fontsLoaded.contains(url)) {
      _loadFont(url, () {
        if (mounted) setState(() {});
      });
    }
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
        final k = (w / 640).clamp(0.5, 2.5).toDouble();
        final tickerH = tickerText.isEmpty ? 0.0 : (22 * k).clamp(16.0, 46.0).toDouble();
        final margin = 10 * k;
        final top = b.logoCorner.startsWith('h');
        final left = b.logoCorner.endsWith('g');
        return Stack(clipBehavior: Clip.hardEdge, children: [
          if (b.logoShow)
            Positioned(
              top: top ? margin : null,
              bottom: top ? null : margin + tickerH,
              left: left ? margin : null,
              right: left ? null : margin,
              child: Opacity(
                opacity: b.logoOpacity / 100,
                // Notre logo officiel, avec le reflet de lumière qui le traverse (comme dans l'appli).
                child: b.logoUrl != null
                    ? SizedBox(
                        width: w * 0.17 * b.logoSize / 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3 * k),
                          child: Image.network(b.logoUrl!, fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => LogoShine(width: w * 0.17 * b.logoSize / 100, radius: 3 * k)),
                        ),
                      )
                    : LogoShine(width: w * 0.17 * b.logoSize / 100, radius: 3 * k),
              ),
            ),
          if (slot != null && slot.program.hasBand)
            Positioned(
              left: 0,
              right: 0,
              bottom: tickerH + 14 * k,
              child: Center(
                child: _Band(
                  visible: bandOn,
                  anim: b.bandAnim,
                  artist: (slot.program.artist ?? '').trim(),
                  song: (slot.program.song ?? '').trim(),
                  k: k,
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
              child: RepaintBoundary(child: _Ticker(text: tickerText, speed: b.tickerSpeed, theme: b.tickerTheme, height: tickerH, branding: b)),
            ),
        ]);
      }),
    );
  }
}

/// Bande artiste : nom sur le dégradé du logo (en mouvement lent), titre sur fond blanc.
class _Band extends StatefulWidget {
  const _Band({required this.visible, required this.anim, required this.artist, required this.song, required this.k, required this.branding});

  final bool visible;
  final String anim;
  final String artist;
  final String song;
  final double k;
  final Branding branding;

  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> with SingleTickerProviderStateMixin {
  // Le dégradé ne bouge que pendant que la bande est à l'écran (rien à calculer le reste du temps).
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(seconds: 9));

  void _syncFlow() {
    if (widget.visible && !_flow.isAnimating) {
      _flow.repeat(reverse: true);
    } else if (!widget.visible && _flow.isAnimating) {
      Future.delayed(const Duration(milliseconds: 800), () {
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
    if (old.visible != widget.visible) _syncFlow();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.k;
    final b = widget.branding;
    final card = ConstrainedBox(
      constraints: BoxConstraints(minWidth: 150 * k, maxWidth: 330 * k),
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
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 - 2 * v, 0),
                        end: Alignment(3 - 2 * v, 0),
                        colors: const [AppColors.sunYellow, AppColors.sunMid, Color(0xFFFFB347), AppColors.sunYellow],
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
                      style: brandStyle(b, size: 14 * k, weight: FontWeight.w800, color: AppColors.navy)),
                ),
              ),
            if (widget.song.isNotEmpty)
              ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 3 * k),
                  child: Text(widget.song,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: brandStyle(b, size: 10.5 * k, weight: FontWeight.w600, color: AppColors.navy)),
                ),
              ),
          ]),
        ),
      ),
    );
    final on = widget.visible;
    switch (widget.anim) {
      case 'fade':
        return AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 700), child: card);
      case 'open':
        return AnimatedScale(
          scale: on ? 1 : 0.2,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 350), child: card),
        );
      default:
        return AnimatedSlide(
          offset: on ? Offset.zero : const Offset(0, 1.6),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 450), child: card),
        );
    }
  }
}

/// Bandeau d'infos défilant en bas de l'image.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.text, required this.speed, required this.theme, required this.height, required this.branding});

  final String text;
  final int speed;
  final String theme;
  final double height;
  final Branding branding;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 20));
  double _cycle = 1;
  String? _key;

  Color get _fg => switch (widget.theme) { 'blanc' => AppColors.navy, 'noir' => AppColors.sunYellow, _ => Colors.white };
  Color get _bg => switch (widget.theme) { 'blanc' => Colors.white, 'noir' => const Color(0xD9000000), _ => const Color(0xEB0B1463) };

  TextStyle get _style => brandStyle(widget.branding, size: widget.height * 0.52, weight: FontWeight.w500, color: _fg);

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
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Ticker old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.speed != widget.speed || old.height != widget.height || old.branding.fontName != widget.branding.fontName) {
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
          child: Text('INFO', style: brandStyle(widget.branding, size: h * 0.42, weight: FontWeight.w800, color: AppColors.navy)),
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
