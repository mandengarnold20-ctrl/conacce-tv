import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Web (iPhone, Android, ordinateur) : la vidéo YouTube / Facebook joue dans l'appli,
/// comme si elle y avait été téléchargée.
class EmbedVideo extends StatelessWidget {
  const EmbedVideo({super.key, required this.embedUrl, required this.sourceUrl, this.coverUrl});

  final String embedUrl;
  final String sourceUrl;
  final String? coverUrl;

  static final _registered = <String>{};

  static String _viewType(String url) {
    final type = 'conacce-embed-${url.hashCode}';
    if (_registered.add(type)) {
      ui_web.platformViewRegistry.registerViewFactory(type, (int viewId) {
        final document = globalContext['document'] as JSObject;
        final frame = document.callMethod<JSObject>('createElement'.toJS, 'iframe'.toJS);
        frame['src'] = url.toJS;
        frame.callMethod<JSAny?>('setAttribute'.toJS, 'allow'.toJS,
            'autoplay; encrypted-media; picture-in-picture; fullscreen; web-share'.toJS);
        frame.callMethod<JSAny?>('setAttribute'.toJS, 'allowfullscreen'.toJS, 'true'.toJS);
        frame.callMethod<JSAny?>('setAttribute'.toJS, 'frameborder'.toJS, '0'.toJS);
        final style = frame['style'] as JSObject;
        style['border'] = '0'.toJS;
        style['width'] = '100%'.toJS;
        style['height'] = '100%'.toJS;
        style['backgroundColor'] = '#000'.toJS;
        return frame;
      });
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(color: Colors.black, child: HtmlElementView(viewType: _viewType(embedUrl))),
    );
  }
}
