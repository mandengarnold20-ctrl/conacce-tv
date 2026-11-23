import 'dart:js_interop';

@JS('conacceFullscreen')
external void _conacceFullscreen();

@JS('conaccePip')
external void _conaccePip();

@JS('conaccePipSupported')
external JSBoolean? _conaccePipSupported();

/// Ouvre la vidéo en plein écran avec le lecteur du téléphone (iPhone, Android).
void requestVideoFullscreen() {
  try {
    _conacceFullscreen();
  } catch (_) {}
}

/// Le navigateur sait-il afficher la vidéo en mini-écran (image dans l'image) ?
bool get pipSupported {
  try {
    return _conaccePipSupported()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Met la TV en mini-écran flottant (ou la ramène dans l'appli si elle y est déjà).
void togglePictureInPicture() {
  try {
    _conaccePip();
  } catch (_) {}
}

@JS('conacceImmersive')
external void _conacceImmersive(JSBoolean on);

/// TV en grand (téléphone tourné) : la page entière (vidéo + logo + bandeau) passe en plein écran
/// au premier toucher, là où le navigateur le permet (Android). Les barres du navigateur disparaissent.
void setPageImmersive(bool on) {
  try {
    _conacceImmersive(on.toJS);
  } catch (_) {}
}
