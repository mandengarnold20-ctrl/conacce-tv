import 'dart:js_interop';

@JS('conacceFullscreen')
external void _conacceFullscreen();

/// Ouvre la vidéo en plein écran avec le lecteur du téléphone (iPhone, Android).
void requestVideoFullscreen() {
  try {
    _conacceFullscreen();
  } catch (_) {}
}
