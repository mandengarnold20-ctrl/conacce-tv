import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _tv = false;

/// Le site tourne-t-il dans le navigateur d'un téléviseur (Samsung, LG, Android TV…) ?
bool get isTvDevice => _tv;

/// Téléviseurs reconnus d'après leur navigateur : Samsung (Tizen), LG (webOS), Android TV / Google TV,
/// Fire TV, Sony, Philips, Hisense (VIDAA), HbbTV… On peut aussi forcer avec l'adresse « ?tv=1 ».
Future<void> detectDevice() async {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    final ua = (nav?['userAgent'] as JSString?)?.toDart ?? '';
    final loc = globalContext['location'] as JSObject?;
    final search = (loc?['search'] as JSString?)?.toDart ?? '';
    _tv = search.contains('tv=1') ||
        RegExp(r'Tizen|Web0S|webOS|SMART-TV|SmartTV|HbbTV|NetCast|VIDAA|BRAVIA|AFT[A-Z]|GoogleTV|Android TV|CrKey|PhilipsTV|Roku', caseSensitive: false)
            .hasMatch(ua);
  } catch (_) {
    _tv = false;
  }
}
