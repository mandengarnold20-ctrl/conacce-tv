import 'package:flutter/services.dart';

void requestVideoFullscreen() {}

bool get pipSupported => false;

void togglePictureInPicture() {}

/// Appli Android / iPhone : en grand, on cache aussi les barres du téléphone
/// (heure, batterie, boutons) ; un glissement depuis le bord les fait revenir un instant.
void setPageImmersive(bool on) {
  SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
}
