/// Type d'appareil : téléviseur (Android TV / Google TV, et plus tard Samsung, LG) ou non.
/// Sur un téléviseur, l'appli s'ouvre directement en plein écran sur la chaîne et se pilote
/// à la télécommande.
export 'device_stub.dart' if (dart.library.js_interop) 'device_web.dart' if (dart.library.io) 'device_io.dart';
