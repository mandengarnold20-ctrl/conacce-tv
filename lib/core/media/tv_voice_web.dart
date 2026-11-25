import 'dart:js_interop';

import 'package:flutter/foundation.dart';

/// Sur le web, la baisse de la musique pendant l'annonce est faite directement par la page (web/index.html).
final tvDuck = ValueNotifier<double>(1);

@JS('conacceVoice')
external void _voice(JSString? url, JSNumber off, JSBoolean muted);

/// Annonce vocale calée sur l'horloge de l'antenne (voir tv_voice_stub.dart).
void tvVoiceSync(String? url, double off, {bool muted = false}) {
  try {
    _voice(url?.toJS, off.toJS, muted.toJS);
  } catch (_) {}
}
