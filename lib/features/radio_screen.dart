import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/analytics.dart';
import '../core/media/audio_player_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../data/providers.dart';

/// Radio Dunamis FM : cercle de lumière, égaliseur, lecture en arrière-plan.
class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.watch(radioProvider).valueOrNull;
    final audio = ref.read(audioPlayerServiceProvider);
    final state = ref.watch(audioPlayerStateProvider).valueOrNull;
    final isThis = audio.currentId == 'radio';
    final playing = isThis && (state?.playing ?? false);
    final onAir = radio?.canPlay ?? false;

    Future<void> toggle() async {
      if (!onAir) return;
      if (!isThis) {
        Analytics.radioListen();
        await audio.play(id: 'radio', url: radio!.streamUrl!, title: radio.currentShow ?? radio.name, artist: radio.name, artworkUrl: radio.coverUrl, isLive: true);
      } else {
        playing ? await audio.pause() : await audio.resume();
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 20, 24, 110),
        child: Column(children: [
          LightRing(
            size: 230,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Dunamis', style: AppTheme.title(size: 40, weight: FontWeight.w900).copyWith(letterSpacing: -1)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(gradient: AppColors.sunGradient, borderRadius: BorderRadius.circular(6)),
                child: Text('FM', style: AppTheme.title(size: 18, weight: FontWeight.w900, color: AppColors.navy).copyWith(letterSpacing: 2)),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (onAir) const LiveBadge(),
          const SizedBox(height: 10),
          Text(radio?.name ?? 'Radio Dunamis FM', style: AppTheme.title(size: 21, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            onAir ? [radio?.currentShow, radio?.host].whereType<String>().join(' · ') : 'La radio n’émet pas en ce moment.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mist, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _Equalizer(active: playing),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.outlined(
              tooltip: 'Partager',
              iconSize: 22,
              style: IconButton.styleFrom(side: const BorderSide(color: Color(0x2EFFFFFF)), minimumSize: const Size(52, 52)),
              onPressed: () => Share.share('Écoutez ${radio?.name ?? 'Radio Dunamis FM'} sur l’appli Conacce TV !'),
              icon: const Icon(Icons.share_rounded, color: Colors.white),
            ),
            const SizedBox(width: 26),
            Semantics(
              button: true,
              label: playing ? 'Pause' : 'Écouter',
              child: GestureDetector(
                onTap: onAir ? toggle : null,
                child: Opacity(
                  opacity: onAir ? 1 : .4,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.sunGradient,
                      boxShadow: [BoxShadow(color: Color(0x73FA5304), blurRadius: 30, offset: Offset(0, 10))],
                    ),
                    child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40, color: AppColors.navy),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 26),
            const SizedBox(width: 52),
          ]),
          const SizedBox(height: 12),
          const Text('L’écoute continue écran éteint.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.active});

  final bool active;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  static const _colors = [AppColors.sunYellow, AppColors.sunYellow, AppColors.sunGold, AppColors.sunMid, AppColors.sunMid, AppColors.sunDeep, AppColors.sunOrange, AppColors.sunDeep, AppColors.sunMid, AppColors.sunGold, AppColors.sunYellow];

  @override
  void didUpdateWidget(_Equalizer old) {
    super.didUpdateWidget(old);
    widget.active ? _c.repeat(reverse: true) : _c.stop();
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _colors.length; i++)
              Container(
                width: 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: widget.active ? 8 + 28 * (((i * 37) % 10) / 10 * .5 + .5 * (i.isEven ? _c.value : 1 - _c.value)) : 6,
                decoration: BoxDecoration(color: _colors[i], borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ),
    );
  }
}
