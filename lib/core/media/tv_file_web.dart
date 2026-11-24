import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

@JS('conacceFilePlay')
external void _play(JSString url, JSNumber startSeconds, JSString key);

@JS('conacceFilePreload')
external void _preload(JSString url);

@JS('conacceFileAway')
external void _away();

const _viewType = 'conacce-tv-file';
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
    // Les touchers passent à l'appli (bouton Agrandir) ; le son s'active quand même au premier toucher.
    style['pointerEvents'] = 'none'.toJS;
    globalContext.callMethod<JSAny?>('conacceFileHost'.toJS, host);
    return host;
  });
}

/// TV : vidéos envoyées (Cloudflare) lues par un lecteur unique gardé pendant toute la visite.
/// Le programme suivant est préparé à l'avance ; changer de page ne recharge rien.
class TvFileSurface extends StatefulWidget {
  const TvFileSurface({
    super.key,
    required this.url,
    required this.slotKey,
    required this.position,
    required this.remaining,
    this.nextUrl,
    this.onExpand,
    this.expanded = false,
  });

  final String url;
  final String slotKey;
  final Duration Function() position;
  final Duration Function() remaining;

  /// Programme suivant (s'il s'agit aussi d'une vidéo envoyée) : préparé ~40 s avant.
  final String? nextUrl;
  final VoidCallback? onExpand;
  final bool expanded;

  @override
  State<TvFileSurface> createState() => _TvFileSurfaceState();
}

class _TvFileSurfaceState extends State<TvFileSurface> {
  Timer? _timer;
  String? _preloaded;
  bool _showBtn = false;
  Timer? _btnTimer;

  @override
  void initState() {
    super.initState();
    _register();
    _start();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _maybePreload());
  }

  void _start() {
    try {
      _play(widget.url.toJS, (widget.position().inMilliseconds / 1000).toJS, widget.slotKey.toJS);
    } catch (_) {}
  }

  void _maybePreload() {
    final next = widget.nextUrl;
    if (next == null || next == widget.url || next == _preloaded) return;
    if (widget.remaining() > const Duration(seconds: 40)) return;
    _preloaded = next;
    try {
      _preload(next.toJS);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(TvFileSurface old) {
    super.didUpdateWidget(old);
    if (old.slotKey != widget.slotKey || old.url != widget.url) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _btnTimer?.cancel();
    try {
      _away();
    } catch (_) {}
    super.dispose();
  }

  void _reveal() {
    _btnTimer?.cancel();
    if (!_showBtn) setState(() => _showBtn = true);
    _btnTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showBtn = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _reveal(),
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black, child: HtmlElementView(viewType: _viewType)),
          if (widget.onExpand != null)
            Positioned(
              left: 8,
              top: 8,
              child: IgnorePointer(
                ignoring: !_showBtn,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _showBtn ? 1 : 0,
                  child: Material(
                    color: const Color(0x80000000),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: widget.expanded ? 'Réduire' : 'Agrandir',
                      icon: Icon(widget.expanded ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                      onPressed: widget.onExpand,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
