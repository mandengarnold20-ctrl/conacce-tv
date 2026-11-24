/// Réserve hors connexion : téléchargement à l'avance des programmes de la chaîne.
/// Web : en pause (le navigateur ne garde pas les vidéos de façon fiable) ;
/// appli Android : vidéos gardées dans le téléphone.
export 'offline_stub.dart' if (dart.library.js_interop) 'offline_web.dart' if (dart.library.io) 'offline_io.dart';
