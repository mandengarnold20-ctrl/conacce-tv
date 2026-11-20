import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

@JS('conacceTvPlay')
external void _play(JSString videoId, JSNumber startSeconds, JSString key);

@JS('conacceTvStop')
external void _stop(JSString key);

@JS('conacceTvUnmute')
external void _unmute();

const _viewType = 'conacce-tv-youtube';
bool _registered = false;

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final document = globalContext['document'] as JSObject;
    final host = document.callMethod<JSObject>('createElement'.toJS, 'div'.toJS);
    final style = host['style'] as JSObject;
    style['position'] = 'relative'.toJS;
    style['width'] = '100%'.toJS;
    style['height'] = '100%'.toJS;
    style['backgroundColor'] = '#000'.toJS;
    style['overflow'] = 'hidden'.toJS;
    globalContext.callMethod<JSAny?>('conacceTvHost'.toJS, host);
    return host;
  });
}

/// Le son est-il coupé (lecture automatique avec son refusée par le navigateur) ?
bool get tvYoutubeMuted {
  try {
    return (globalContext['conacceTvMuted'] as JSBoolean?)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

void tvYoutubeUnmute() {
  try {
    _unmute();
  } catch (_) {}
}

/// Lecteur YouTube de la chaîne : sans boutons, calé sur l'horaire de la grille.
/// La vidéo suivante se prépare par-dessus et n'apparaît que lorsqu'elle joue déjà.
class TvYoutubeSurface extends StatefulWidget {
  const TvYoutubeSurface({super.key, required this.videoId, required this.slotKey, required this.position});

  final String videoId;
  final String slotKey;
  final Duration Function() position;

  @override
  State<TvYoutubeSurface> createState() => _TvYoutubeSurfaceState();
}

class _TvYoutubeSurfaceState extends State<TvYoutubeSurface> {
  @override
  void initState() {
    super.initState();
    _register();
    _start();
  }

  void _start() {
    try {
      _play(widget.videoId.toJS, (widget.position().inMilliseconds / 1000).toJS, widget.slotKey.toJS);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(TvYoutubeSurface old) {
    super.didUpdateWidget(old);
    if (old.slotKey != widget.slotKey) _start();
  }

  @override
  void dispose() {
    try {
      _stop(widget.slotKey.toJS);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(color: Colors.black, child: HtmlElementView(viewType: _viewType)),
    );
  }
}
