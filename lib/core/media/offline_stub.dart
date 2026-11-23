/// Applications Android / iOS : la réserve hors connexion arrive avec la version boutique.
void offlinePlan(String json) {}

/// État de la réserve : (programmes prêts, total, Mo téléchargés, en cours).
({int ready, int total, double mb, bool busy})? offlineStatus() => null;
