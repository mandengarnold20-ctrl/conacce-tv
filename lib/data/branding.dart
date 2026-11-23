/// Habillage de la chaîne, réglé depuis la régie (table tv_branding).
class TickerMessage {
  const TickerMessage({required this.text, this.from, this.to});

  final String text;

  /// Heures de diffusion « HH:mm » (heure du Bénin). Vides = toute la journée.
  final String? from;
  final String? to;

  static int? _min(String? hm) {
    if (hm == null || !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(hm)) return null;
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  /// Le message passe-t-il à cette minute de la journée (0–1439) ?
  bool activeAt(int minute) {
    final a = _min(from), b = _min(to);
    if (a == null || b == null) return true;
    return a <= b ? (minute >= a && minute < b) : (minute >= a || minute < b);
  }

  factory TickerMessage.fromMap(Map m) =>
      TickerMessage(text: (m['text'] ?? '').toString(), from: m['from']?.toString(), to: m['to']?.toString());
}

class Branding {
  const Branding({
    this.logoShow = true,
    this.logoCorner = 'hd',
    this.logoSize = 100,
    this.logoOpacity = 90,
    this.logoUrl,
    this.tickerShow = true,
    this.tickerText = '',
    this.tickerSpeed = 3,
    this.tickerTheme = 'nuit',
    this.messages = const [],
    this.bandShow = true,
    this.bandAnim = 'slide',
    this.bandAt = 15,
    this.bandDur = 8,
    this.bandEnd = 30,
    this.fontName = 'Poppins',
    this.fontUrl,
  });

  final bool logoShow;
  final String logoCorner; // hg, hd, bg, bd
  final int logoSize; // %
  final int logoOpacity; // %
  final String? logoUrl;
  final bool tickerShow;
  final String tickerText;
  final int tickerSpeed; // 1 à 5
  final String tickerTheme; // nuit, blanc, noir
  final List<TickerMessage> messages;
  final bool bandShow;
  final String bandAnim; // slide, fade, open
  final int bandAt; // secondes après le début du clip
  final int bandDur; // secondes à l'écran
  final int bandEnd; // 2e passage : secondes avant la fin (0 = aucun)
  final String fontName;
  final String? fontUrl;

  /// Texte du bandeau à cet instant : message principal + messages programmés en cours.
  String tickerAt(DateTime utc) {
    final local = utc.toUtc().add(const Duration(hours: 1)); // heure du Bénin
    final minute = local.hour * 60 + local.minute;
    final parts = <String>[
      if (tickerText.trim().isNotEmpty) tickerText.trim(),
      for (final m in messages)
        if (m.text.trim().isNotEmpty && m.activeAt(minute)) m.text.trim(),
    ];
    return parts.join('   •   ');
  }

  static int _int(Object? v, int def) => v is num ? v.toInt() : int.tryParse('$v') ?? def;
  static bool _bool(Object? v, bool def) => v is bool ? v : def;
  static String? _str(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';

  factory Branding.fromConfig(Map<String, dynamic>? c) {
    if (c == null) return const Branding();
    final logo = (c['logo'] as Map?) ?? const {};
    final ticker = (c['ticker'] as Map?) ?? const {};
    final band = (c['band'] as Map?) ?? const {};
    final font = (c['font'] as Map?) ?? const {};
    return Branding(
      logoShow: _bool(logo['show'], true),
      logoCorner: _str(logo['corner']) ?? 'hd',
      logoSize: _int(logo['size'], 100).clamp(40, 200).toInt(),
      logoOpacity: _int(logo['opacity'], 90).clamp(10, 100).toInt(),
      logoUrl: _str(logo['url']),
      tickerShow: _bool(ticker['show'], true),
      tickerText: _str(ticker['text']) ?? '',
      tickerSpeed: _int(ticker['speed'], 3).clamp(1, 5).toInt(),
      tickerTheme: _str(ticker['theme']) ?? 'nuit',
      messages: [
        for (final m in (ticker['messages'] as List?) ?? const [])
          if (m is Map) TickerMessage.fromMap(m),
      ],
      bandShow: _bool(band['show'], true),
      bandAnim: _str(band['anim']) ?? 'slide',
      bandAt: _int(band['at'], 15).clamp(0, 3600).toInt(),
      bandDur: _int(band['dur'], 8).clamp(2, 60).toInt(),
      bandEnd: _int(band['end'], 30).clamp(0, 3600).toInt(),
      fontName: _str(font['name']) ?? 'Poppins',
      fontUrl: _str(font['url']),
    );
  }
}
