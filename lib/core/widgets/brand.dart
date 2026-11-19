import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Fond à vagues bleues (bleu roi en haut → bleu nuit en bas).
class WaveBackground extends StatefulWidget {
  const WaveBackground({super.key, required this.child});

  final Widget child;

  @override
  State<WaveBackground> createState() => _WaveBackgroundState();
}

/// Fond bleu dont les vagues ondulent doucement (cycle doux de 12 s).
class _WaveBackgroundState extends State<WaveBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value * 2 * math.pi;
              // Léger balancement de l'image de fond. L'image est toujours assez agrandie
              // pour que le mouvement ne découvre jamais les bords de l'écran.
              final size = MediaQuery.sizeOf(context);
              final minScale = 1 + 2 * 16 / math.max(1, math.min(size.width, size.height)) + .06;
              return Transform.translate(
                offset: Offset(math.sin(t) * 14, math.cos(t) * 10),
                child: Transform.scale(
                  scale: minScale + (math.sin(t) + 1) * 0.01,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.royal,
                      image: DecorationImage(image: AssetImage('assets/images/fond.jpg'), fit: BoxFit.cover),
                    ),
                  ),
                ),
              );
            },
          ),
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _WavesPainter(_c.value)),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _WavesPainter extends CustomPainter {
  _WavesPainter(this.v);

  final double v;

  void _wave(Canvas canvas, Size size, double baseY, double amp, double phase, double length, Color top, Color bottom) {
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width + 8; x += 8) {
      final y = baseY + math.sin(x / size.width * 2 * math.pi * length + phase) * amp;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])
          .createShader(Rect.fromLTWH(0, baseY - amp, size.width, size.height - baseY + amp));
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = v * 2 * math.pi;
    final h = size.height;
    _wave(canvas, size, h * 0.60, h * 0.06, t, 0.9, const Color(0x400D2389), const Color(0x55080F43));
    _wave(canvas, size, h * 0.78, h * 0.05, -t + 1.4, 1.2, const Color(0x40080F43), const Color(0x77050A2E));
  }

  @override
  bool shouldRepaint(_WavesPainter old) => old.v != v;
}

/// Logo Conacce TV traversé par un reflet de lumière toutes les quelques secondes.
class LogoShine extends StatefulWidget {
  const LogoShine({super.key, this.width = 300, this.radius = 6});

  final double width;
  final double radius;

  @override
  State<LogoShine> createState() => _LogoShineState();
}

class _LogoShineState extends State<LogoShine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Conacce TV',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width,
          child: Stack(
            children: [
              Image.asset('assets/images/logo.png', width: widget.width, fit: BoxFit.fitWidth),
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    // Le reflet passe pendant les 30 % finaux de chaque cycle.
                    final t = ((_c.value - .7) / .3).clamp(0.0, 1.0);
                    final x = -1.6 + t * 3.6;
                    return IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(x - .5, -1),
                            end: Alignment(x + .5, 1),
                            colors: const [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x00FFFFFF)],
                            stops: const [.3, .5, .7],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cercle de lumière tournant (Radio Dunamis FM).
class LightRing extends StatefulWidget {
  const LightRing({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  State<LightRing> createState() => _LightRingState();
}

class _LightRingState extends State<LightRing> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.4,
      height: s * 1.4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => Transform.scale(
              scale: 1 + _pulse.value * .08,
              child: Container(
                width: s * 1.4,
                height: s * 1.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.sunYellow.withValues(alpha: .25 + _pulse.value * .2),
                    AppColors.sunOrange.withValues(alpha: .1),
                    AppColors.sunOrange.withValues(alpha: 0),
                  ], stops: const [0, .45, .72]),
                ),
              ),
            ),
          ),
          RotationTransition(
            turns: _spin,
            child: CustomPaint(size: Size.square(s), painter: _RingPainter()),
          ),
          Container(
            width: s - 30,
            height: s - 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: Alignment(0, -.1), colors: [Color(0xFF14309E), AppColors.navy], stops: [0, .75]),
              boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 30, spreadRadius: -10)],
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          AppColors.sunYellow.withValues(alpha: 0),
          AppColors.sunYellow,
          AppColors.sunMid,
          AppColors.sunOrange,
          AppColors.sunOrange.withValues(alpha: 0),
        ],
        stops: const [0, .25, .45, .58, .83],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 6);
    canvas.drawArc(rect.deflate(6), 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => false;
}

/// Badge rouge « EN DIRECT » avec point clignotant.
class LiveBadge extends StatefulWidget {
  const LiveBadge({super.key, this.label = 'EN DIRECT'});

  final String label;

  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppColors.live, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: .35, end: 1.0).animate(_c),
          child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 6),
        Text(widget.label, style: AppTheme.title(size: 10, weight: FontWeight.w800).copyWith(letterSpacing: 1)),
      ]),
    );
  }
}

/// Carte bleu marine du logo, qui se fond dans le fond.
class NavyCard extends StatelessWidget {
  const NavyCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.radius = 18});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Bouton principal au dégradé du soleil.
class SunButton extends StatelessWidget {
  const SunButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 48});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(height / 2)),
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null) ...[Icon(icon, color: AppColors.navy, size: 20), const SizedBox(width: 8)],
                Text(label, style: AppTheme.title(size: 14, weight: FontWeight.w700, color: AppColors.navy)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Titre de section avec lien « Tout voir ».
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
      child: Row(children: [
        Expanded(child: Text(title, style: AppTheme.title(size: 16, weight: FontWeight.w800))),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('Tout voir', style: TextStyle(color: AppColors.sunYellow, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Image réseau (vignette, couverture) avec repli en dégradé.
class NetCover extends StatelessWidget {
  const NetCover({super.key, this.url, this.radius = 12, this.icon = Icons.play_circle_outline_rounded, this.fallback});

  final String? url;
  final double radius;
  final IconData icon;
  final Gradient? fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: fallback ?? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1D4FD8), AppColors.navy]),
      ),
      child: Center(child: Icon(icon, color: Colors.white70)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null || url!.isEmpty
          ? placeholder
          : CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, placeholder: (_, __) => const ColoredBox(color: AppColors.navyDeep), errorWidget: (_, __, ___) => placeholder),
    );
  }
}
