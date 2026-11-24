{{flutter_js}}
{{flutter_build_config}}

// Pas de « service worker » : chaque ouverture charge toujours la dernière version de l'appli.
// Moteur d'affichage servi depuis notre propre adresse (pas de serveur extérieur à joindre au démarrage).
_flutter.loader.load({ config: { canvasKitBaseUrl: 'canvaskit/' } });
