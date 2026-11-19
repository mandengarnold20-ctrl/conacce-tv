/// Connexion à la base Conacce TV (Supabase).
///
/// Valeurs par défaut = projet Supabase « conacce-tv ». La clé « publishable » est faite
/// pour être dans l'appli (la sécurité est assurée par les règles RLS). On peut aussi
/// les passer à la compilation :
/// flutter build ... --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://nidvzxeyqasvspmtdfcu.supabase.co');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_0YuinNEK3O-9dYV7xacbsQ_9Wu2e2s8');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
