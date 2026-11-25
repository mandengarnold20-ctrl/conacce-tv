import 'dart:ui' show Color;

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

/// Une police : celles de la chaîne (fichiers hébergés avec l'appli, dossier fonts/),
/// ou une police importée en régie (adresse du fichier).
class BrandFont {
  const BrandFont(this.name, [this.url]);

  final String name;
  final String? url;

  /// Polices proposées en régie, avec leurs fichiers (hébergés avec l'appli : même rendu partout).
  static const builtIn = <String, List<String>>{
    'Poppins': ['poppins-500.ttf', 'poppins-800.ttf'],
    'Montserrat': ['montserrat.ttf'],
    'Inter': ['inter.ttf'],
    'Raleway': ['raleway.ttf'],
    'Oswald': ['oswald.ttf'],
    'Bebas Neue': ['bebasneue.ttf'],
    'Anton': ['anton.ttf'],
    'Playfair Display': ['playfairdisplay.ttf'],
    'Roboto': ['roboto.ttf'],
    'Open Sans': ['opensans.ttf'],
    'Lato': ['lato-500.ttf', 'lato-800.ttf'],
    'Nunito': ['nunito.ttf'],
    'Ubuntu': ['ubuntu-500.ttf', 'ubuntu-700.ttf'],
    'Barlow': ['barlow-500.ttf', 'barlow-800.ttf'],
    'Archivo Black': ['archivoblack.ttf'],
    'Righteous': ['righteous.ttf'],
  };

  /// Clé unique pour le chargement (adresse importée, ou nom d'une police de la chaîne).
  String get key => url ?? 'builtin:$name';

  /// Fichiers à charger (adresses relatives au site pour les polices de la chaîne).
  List<String> get files => url != null ? [url!] : [for (final f in builtIn[name] ?? builtIn['Poppins']!) 'fonts/$f'];

  static BrandFont? fromMap(Object? m) {
    if (m is! Map) return null;
    final n = m['name']?.toString().trim() ?? '';
    if (n.isEmpty) return null;
    final u = m['url']?.toString().trim();
    return BrandFont(n, u == null || u.isEmpty ? null : u);
  }
}

class Branding {
  const Branding({
    this.logoShow = true,
    this.logoCorner = 'hd',
    this.logoX,
    this.logoY,
    this.logoSize = 100,
    this.logoOpacity = 90,
    this.logoUrl,
    this.tickerShow = true,
    this.tickerText = '',
    this.tickerFallback = '',
    this.tickerSpeed = 3,
    this.tickerTheme = 'nuit',
    this.tickerBg,
    this.tickerFg,
    this.tickerOnMin = 0,
    this.tickerEveryMin = 0,
    this.messages = const [],
    this.bandShow = true,
    this.bandAnim = 'slide',
    this.bandAnimOut = 'slide',
    this.bandAt = 15,
    this.bandDur = 8,
    this.bandEnd = 30,
    this.bandPos = 'bc',
    this.bandY = 0,
    this.bandScale = 100,
    this.bandWidth = 52,
    this.bandTopA = const Color(0xFFF9CA22),
    this.bandTopB = const Color(0xFFFD9113),
    this.bandTopText = const Color(0xFF0B1463),
    this.bandBottomBg = const Color(0xFFFFFFFF),
    this.bandBottomText = const Color(0xFF0B1463),
    this.bandImg,
    this.bandImgAspect = 6,
    this.bandTextSize = 100,
    this.bandImgText = const Color(0xFFFFFFFF),
    this.bandImg2,
    this.bandImg2Aspect = 6,
    this.bandImgText2,
    this.bandW1,
    this.bandW2,
    this.bandX1,
    this.bandY1,
    this.bandX2,
    this.bandY2,
    this.rankBg = const Color(0xFFFFFFFF),
    this.rankFg = const Color(0xFF000000),
    this.rankSide = 'g',
    this.chartBandAll = false,
    this.rankCut = true,
    this.chartRankAll = false,
    this.font = const BrandFont('Poppins'),
    this.fontTicker,
    this.fontBand,
  });

  final bool logoShow;
  final String logoCorner; // hg, hd, bg, bd

  /// Position libre réglée à la souris dans la régie (coin haut-gauche du logo, en fraction de l'écran) ;
  /// null = le logo est dans le coin [logoCorner].
  final double? logoX;
  final double? logoY;
  final int logoSize; // %
  final int logoOpacity; // %
  final String? logoUrl;
  final bool tickerShow;
  final String tickerText;

  /// Message de repli : affiché quand il n'y a ni message principal ni message programmé en cours.
  final String tickerFallback;
  final int tickerSpeed; // 1 à 5
  final String tickerTheme; // nuit, blanc, noir (couleurs prêtes)
  final Color? tickerBg; // couleurs libres (prioritaires sur le thème)
  final Color? tickerFg;

  /// Durée de défilement : le bandeau passe [tickerOnMin] minutes toutes les [tickerEveryMin] minutes.
  /// 0 = en continu.
  final int tickerOnMin;
  final int tickerEveryMin;
  final List<TickerMessage> messages;
  final bool bandShow;
  final String bandAnim; // entrée : slide, fade, open
  final String bandAnimOut; // sortie : slide, fade, open
  final int bandAt; // secondes après le début du clip
  final int bandDur; // secondes à l'écran
  final int bandEnd; // 2e passage : secondes avant la fin (0 = aucun)
  final String bandPos; // b|h + g|c|d (bas/haut, gauche/centre/droite)
  final int bandY; // hauteur : décalage en % de l'image (0–40)
  final int bandScale; // taille du texte en % (60–160)
  final int bandWidth; // longueur maximale en % de la largeur (25–90)
  final Color bandTopA, bandTopB, bandTopText, bandBottomBg, bandBottomText;

  /// Image de bande importée dans la régie (null = bande Conacce en deux couleurs).
  /// Le texte (artiste, titre) s'adapte à sa surface.
  final String? bandImg;
  final double bandImgAspect; // largeur / hauteur de l'image
  final int bandTextSize; // taille du texte sur l'image, en % (50–200)
  final Color bandImgText;

  /// 2ᵉ image de bande (titre) : avec deux images, la bande 1 porte l'artiste et la bande 2 le titre.
  final String? bandImg2;
  final double bandImg2Aspect;
  final Color? bandImgText2;

  /// Largeur de chaque bande (% de l'écran) et position réglée à la souris (coin haut-gauche, fraction de l'écran).
  final int? bandW1, bandW2;
  final double? bandX1, bandY1, bandX2, bandY2;

  /// Numéro du classement (hits de la semaine) collé à la bande 1.
  final Color rankBg, rankFg;
  final String rankSide; // g (à gauche) ou d (à droite)

  /// Pendant un classement : bandes et/ou numéro affichés pendant tout le clip (sinon au rythme habituel des bandes).
  final bool chartBandAll, chartRankAll;

  /// Chiffre « percé » dans le carré (on voit l'image à travers), sinon chiffre de couleur.
  final bool rankCut;

  bool get twoBands => bandImg != null && bandImg2 != null;
  final BrandFont font; // police générale
  final BrandFont? fontTicker; // police du bandeau (sinon la générale)
  final BrandFont? fontBand; // police de la bande artiste (sinon la générale)

  // Compatibilité : anciens noms.
  String get fontName => font.name;
  String? get fontUrl => font.url;

  BrandFont get tickerFont => fontTicker ?? font;
  BrandFont get bandFont => fontBand ?? font;

  static int _beninMinute(DateTime utc) {
    final local = utc.toUtc().add(const Duration(hours: 1)); // heure du Bénin
    return local.hour * 60 + local.minute;
  }

  /// Texte du bandeau à cet instant : message principal + messages programmés en cours,
  /// ou le message de repli s'il n'y a rien d'autre. Vide = bandeau caché.
  String tickerAt(DateTime utc) {
    final minute = _beninMinute(utc);
    if (tickerOnMin > 0 && tickerEveryMin > tickerOnMin && minute % tickerEveryMin >= tickerOnMin) return '';
    final parts = <String>[
      if (tickerText.trim().isNotEmpty) tickerText.trim(),
      for (final m in messages)
        if (m.text.trim().isNotEmpty && m.activeAt(minute)) m.text.trim(),
    ];
    if (parts.isEmpty && tickerFallback.trim().isNotEmpty) parts.add(tickerFallback.trim());
    return parts.join('   •   ');
  }

  static double? _frac(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0).toDouble() : null;
  static int _int(Object? v, int def) => v is num ? v.toInt() : int.tryParse('$v') ?? def;
  static bool _bool(Object? v, bool def) => v is bool ? v : def;
  static String? _str(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
  static Color? _color(Object? v) {
    final s = _str(v)?.replaceAll('#', '');
    if (s == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
    return Color(0xFF000000 | int.parse(s, radix: 16));
  }

  factory Branding.fromConfig(Map<String, dynamic>? c) {
    if (c == null) return const Branding();
    final logo = (c['logo'] as Map?) ?? const {};
    final ticker = (c['ticker'] as Map?) ?? const {};
    final band = (c['band'] as Map?) ?? const {};
    const d = Branding();
    final anim = _str(band['anim']) ?? 'slide';
    return Branding(
      logoShow: _bool(logo['show'], true),
      logoCorner: _str(logo['corner']) ?? 'hd',
      logoX: _frac(logo['x']),
      logoY: _frac(logo['y']),
      logoSize: _int(logo['size'], 100).clamp(40, 200).toInt(),
      logoOpacity: _int(logo['opacity'], 90).clamp(10, 100).toInt(),
      logoUrl: _str(logo['url']),
      tickerShow: _bool(ticker['show'], true),
      tickerText: _str(ticker['text']) ?? '',
      tickerFallback: _str(ticker['fallback']) ?? '',
      tickerSpeed: _int(ticker['speed'], 3).clamp(1, 5).toInt(),
      tickerTheme: _str(ticker['theme']) ?? 'nuit',
      tickerBg: _color(ticker['bg']),
      tickerFg: _color(ticker['fg']),
      tickerOnMin: _int(ticker['on'], 0).clamp(0, 1440).toInt(),
      tickerEveryMin: _int(ticker['every'], 0).clamp(0, 1440).toInt(),
      messages: [
        for (final m in (ticker['messages'] as List?) ?? const [])
          if (m is Map) TickerMessage.fromMap(m),
      ],
      bandShow: _bool(band['show'], true),
      bandAnim: anim,
      bandAnimOut: _str(band['out']) ?? anim,
      bandAt: _int(band['at'], 15).clamp(0, 3600).toInt(),
      bandDur: _int(band['dur'], 8).clamp(2, 60).toInt(),
      bandEnd: _int(band['end'], 30).clamp(0, 3600).toInt(),
      bandPos: _str(band['pos']) ?? 'bc',
      bandY: _int(band['y'], 0).clamp(0, 40).toInt(),
      bandScale: _int(band['scale'], 100).clamp(60, 160).toInt(),
      bandWidth: _int(band['width'], 52).clamp(25, 90).toInt(),
      bandTopA: _color(band['topA']) ?? d.bandTopA,
      bandTopB: _color(band['topB']) ?? d.bandTopB,
      bandTopText: _color(band['topText']) ?? d.bandTopText,
      bandBottomBg: _color(band['bottomBg']) ?? d.bandBottomBg,
      bandBottomText: _color(band['bottomText']) ?? d.bandBottomText,
      bandImg: _str(band['img']),
      bandImgAspect: band['ia'] is num ? (band['ia'] as num).toDouble().clamp(1.0, 30.0).toDouble() : 6,
      bandTextSize: _int(band['tsz'], 100).clamp(50, 200).toInt(),
      bandImgText: _color(band['tc']) ?? d.bandImgText,
      bandImg2: _str(band['img2']),
      bandImg2Aspect: band['ia2'] is num ? (band['ia2'] as num).toDouble().clamp(1.0, 30.0).toDouble() : 6,
      bandImgText2: _color(band['tc2']),
      bandW1: band['w1'] is num ? (band['w1'] as num).toInt().clamp(10, 95).toInt() : null,
      bandW2: band['w2'] is num ? (band['w2'] as num).toInt().clamp(10, 95).toInt() : null,
      bandX1: _frac(band['x1']),
      bandY1: _frac(band['y1']),
      bandX2: _frac(band['x2']),
      bandY2: _frac(band['y2']),
      rankBg: _color(band['rankBg']) ?? d.rankBg,
      rankFg: _color(band['rankFg']) ?? d.rankFg,
      rankSide: _str(band['rankSide']) == 'd' ? 'd' : 'g',
      chartBandAll: band['cBand'] == 'all',
      rankCut: band['rankCut'] != false,
      chartRankAll: band['cRank'] == 'all',
      font: BrandFont.fromMap(c['font']) ?? const BrandFont('Poppins'),
      fontTicker: BrandFont.fromMap(c['fontTicker']),
      fontBand: BrandFont.fromMap(c['fontBand']),
    );
  }
}
