import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('conacceOfflinePlan')
external void _plan(JSString json);

void offlinePlan(String json) {
  try {
    _plan(json.toJS);
  } catch (_) {}
}

({int ready, int total, double mb, bool busy})? offlineStatus() {
  try {
    final s = globalContext['conacceOfflineStatus'];
    if (s == null || s.isUndefinedOrNull) return null;
    final o = s as JSObject;
    num n(String k) => (o[k] as JSNumber?)?.toDartDouble ?? 0;
    return (
      ready: n('ready').toInt(),
      total: n('total').toInt(),
      mb: n('mb').toDouble(),
      busy: (o['busy'] as JSBoolean?)?.toDart ?? false,
    );
  } catch (_) {
    return null;
  }
}
