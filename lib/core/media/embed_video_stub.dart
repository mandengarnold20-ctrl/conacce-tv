import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../widgets/brand.dart';

/// Applications Android / iOS : la vidéo s'ouvre dans YouTube ou Facebook.
class EmbedVideo extends StatelessWidget {
  const EmbedVideo({super.key, required this.embedUrl, required this.sourceUrl, this.coverUrl});

  final String embedUrl;
  final String sourceUrl;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(fit: StackFit.expand, children: [
        NetCover(url: coverUrl, radius: 0),
        const ColoredBox(color: Color(0x66080F43)),
        Center(
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.sunGradient),
              child: const Icon(Icons.play_arrow_rounded, size: 40, color: AppColors.navy),
            ),
          ),
        ),
      ]),
    );
  }
}
