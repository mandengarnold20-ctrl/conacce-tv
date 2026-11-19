/// Modèles de données Conacce TV (tables Supabase du même nom).
library;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// Conacce TV en direct (table live_stream, une seule ligne).
class LiveStream {
  const LiveStream({required this.id, required this.title, required this.isLive, this.hlsUrl, this.speaker, this.messageTitle, this.nextLiveInfo, this.nextLiveAt, this.offlineImageUrl});

  final String id;
  final String title;
  final bool isLive;
  final String? hlsUrl;
  final String? speaker;
  final String? messageTitle;
  final String? nextLiveInfo;
  final DateTime? nextLiveAt;
  final String? offlineImageUrl;

  bool get canPlay => isLive && (hlsUrl?.isNotEmpty ?? false);

  factory LiveStream.fromMap(Map<String, dynamic> m) => LiveStream(
        id: m['id'] as String,
        title: m['title'] as String? ?? 'Conacce TV',
        isLive: m['is_live'] as bool? ?? false,
        hlsUrl: m['hls_url'] as String?,
        speaker: m['speaker'] as String?,
        messageTitle: m['message_title'] as String?,
        nextLiveInfo: m['next_live_info'] as String?,
        nextLiveAt: _date(m['next_live_at']),
        offlineImageUrl: m['offline_image_url'] as String?,
      );
}

/// Radio Dunamis FM (table radio, une seule ligne).
class RadioStation {
  const RadioStation({required this.id, required this.name, required this.isOnAir, this.streamUrl, this.currentShow, this.host, this.coverUrl});

  final String id;
  final String name;
  final bool isOnAir;
  final String? streamUrl;
  final String? currentShow;
  final String? host;
  final String? coverUrl;

  bool get canPlay => isOnAir && (streamUrl?.isNotEmpty ?? false);

  factory RadioStation.fromMap(Map<String, dynamic> m) => RadioStation(
        id: m['id'] as String,
        name: m['name'] as String? ?? 'Radio Dunamis FM',
        isOnAir: m['is_on_air'] as bool? ?? false,
        streamUrl: m['stream_url'] as String?,
        currentShow: m['current_show'] as String?,
        host: m['host'] as String?,
        coverUrl: m['cover_url'] as String?,
      );
}

/// Catégories de cultes.
enum SermonCategory {
  dimanche('Culte du dimanche'),
  enseignement('Enseignement'),
  priere('Prière'),
  special('Culte spécial'),
  autre('Autre');

  const SermonCategory(this.label);
  final String label;

  static SermonCategory fromDb(String? v) => SermonCategory.values.firstWhere((c) => c.name == v, orElse: () => SermonCategory.autre);
}

/// Culte enregistré, publié par l'église (table sermons).
class Sermon {
  const Sermon({
    required this.id,
    required this.title,
    required this.category,
    required this.createdAt,
    this.description,
    this.speaker,
    this.preachedOn,
    this.videoUrl,
    this.audioUrl,
    this.thumbnailUrl,
    this.duration,
    this.isFeatured = false,
    this.isDownloadable = true,
    this.viewCount = 0,
    this.section = 'cultes',
  });

  final String id;
  final String title;
  final SermonCategory category;
  /// « cultes » (onglet Cultes) ou « conacce » (Vidéos Conacce).
  final String section;
  final String? description;
  final String? speaker;
  final DateTime? preachedOn;
  final String? videoUrl;
  final String? audioUrl;
  final String? thumbnailUrl;
  final Duration? duration;
  final bool isFeatured;
  final bool isDownloadable;
  final int viewCount;
  final DateTime createdAt;

  bool get hasVideo => videoUrl?.isNotEmpty ?? false;

  /// Identifiant YouTube si la vidéo est un lien YouTube.
  String? get youtubeId => parseYoutubeId(videoUrl);

  /// Lien Facebook (vidéo publique).
  bool get isFacebook {
    final host = Uri.tryParse(videoUrl?.trim() ?? '')?.host ?? '';
    return host.contains('facebook.com') || host.contains('fb.watch');
  }

  /// Vidéo hébergée sur YouTube ou Facebook : lue dans l'appli via le lecteur intégré.
  bool get isEmbed => youtubeId != null || isFacebook;

  /// Adresse du lecteur intégré (YouTube / Facebook).
  String? get embedUrl {
    final id = youtubeId;
    if (id != null) return 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&rel=0&modestbranding=1';
    if (isFacebook) return 'https://www.facebook.com/plugins/video.php?href=${Uri.encodeComponent(videoUrl!.trim())}&show_text=false&autoplay=true';
    return null;
  }

  /// Image de la vignette : celle choisie par l'admin, sinon celle de YouTube.
  String? get coverUrl {
    if (thumbnailUrl?.isNotEmpty ?? false) return thumbnailUrl;
    final id = youtubeId;
    return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }
  bool get hasAudio => audioUrl?.isNotEmpty ?? false;

  String? get durationLabel {
    final d = duration;
    if (d == null) return null;
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h h ${m.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
  }

  factory Sermon.fromMap(Map<String, dynamic> m) => Sermon(
        id: m['id'] as String,
        title: m['title'] as String,
        category: SermonCategory.fromDb(m['category'] as String?),
        description: m['description'] as String?,
        speaker: m['speaker'] as String?,
        preachedOn: m['preached_on'] == null ? null : DateTime.parse(m['preached_on'] as String),
        videoUrl: m['video_url'] as String?,
        audioUrl: m['audio_url'] as String?,
        thumbnailUrl: m['thumbnail_url'] as String?,
        duration: m['duration'] == null ? null : Duration(seconds: (m['duration'] as num).toInt()),
        isFeatured: m['is_featured'] as bool? ?? false,
        isDownloadable: m['is_downloadable'] as bool? ?? true,
        viewCount: (m['view_count'] as num?)?.toInt() ?? 0,
        section: m['section'] as String? ?? 'cultes',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'category': category.name,
        'description': description,
        'speaker': speaker,
        'preached_on': preachedOn?.toIso8601String().substring(0, 10),
        'video_url': videoUrl,
        'audio_url': audioUrl,
        'thumbnail_url': thumbnailUrl,
        'duration': duration?.inSeconds,
        'is_featured': isFeatured,
        'is_downloadable': isDownloadable,
        'view_count': viewCount,
        'section': section,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

/// Œuvre d'Or : livre de l'homme de Dieu (table works).
class Work {
  const Work({required this.id, required this.title, this.subtitle, this.description, this.coverUrl, this.pdfUrl, this.pages, this.year, this.isFree = true, this.priceLabel, this.buyUrl, this.isFeatured = false});

  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? coverUrl;
  final String? pdfUrl;
  final int? pages;
  final int? year;
  final bool isFree;
  final String? priceLabel;
  final String? buyUrl;
  final bool isFeatured;

  bool get canRead => isFree && (pdfUrl?.isNotEmpty ?? false);

  factory Work.fromMap(Map<String, dynamic> m) => Work(
        id: m['id'] as String,
        title: m['title'] as String,
        subtitle: m['subtitle'] as String?,
        description: m['description'] as String?,
        coverUrl: m['cover_url'] as String?,
        pdfUrl: m['pdf_url'] as String?,
        pages: (m['pages'] as num?)?.toInt(),
        year: (m['year'] as num?)?.toInt(),
        isFree: m['is_free'] as bool? ?? true,
        priceLabel: m['price_label'] as String?,
        buyUrl: m['buy_url'] as String?,
        isFeatured: m['is_featured'] as bool? ?? false,
      );
}

/// Affiche de l'accueil (table home_banners).
class HomeBanner {
  const HomeBanner({required this.id, required this.title, required this.imageUrl, required this.targetType, this.subtitle, this.ctaLabel, this.targetId, this.targetUrl});

  final String id;
  final String title;
  final String? subtitle;
  final String imageUrl;
  final String? ctaLabel;
  final String targetType; // none | live | radio | sermon | work | url
  final String? targetId;
  final String? targetUrl;

  factory HomeBanner.fromMap(Map<String, dynamic> m) => HomeBanner(
        id: m['id'] as String,
        title: m['title'] as String,
        subtitle: m['subtitle'] as String?,
        imageUrl: m['image_url'] as String,
        ctaLabel: m['cta_label'] as String?,
        targetType: m['target_type'] as String? ?? 'none',
        targetId: m['target_id'] as String?,
        targetUrl: m['target_url'] as String?,
      );
}

/// Réglages (table app_settings, id = 1).
class AppSettings {
  const AppSettings({this.manOfGodName, this.donationUrl, this.whatsappUrl, this.facebookUrl, this.youtubeUrl, this.contactEmail, this.websiteUrl});

  final String? manOfGodName;
  final String? donationUrl;
  final String? whatsappUrl;
  final String? facebookUrl;
  final String? youtubeUrl;
  final String? contactEmail;
  final String? websiteUrl;

  /// Site et e-mail de la CONACCE (valeurs par défaut si non renseignés dans l'admin).
  String get website => (websiteUrl?.trim().isNotEmpty ?? false) ? websiteUrl!.trim() : 'https://conaccechaplainsafrique.com';
  String get email => (contactEmail?.trim().isNotEmpty ?? false) ? contactEmail!.trim() : 'contact@conaccechaplainsafrique.com';

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        manOfGodName: m['man_of_god_name'] as String?,
        donationUrl: m['donation_url'] as String?,
        whatsappUrl: m['whatsapp_url'] as String?,
        facebookUrl: m['facebook_url'] as String?,
        youtubeUrl: m['youtube_url'] as String?,
        contactEmail: m['contact_email'] as String?,
        websiteUrl: m['website_url'] as String?,
      );
}

/// Message laissé sous la TV en direct (visible le jour même, puis archivé).
class LiveComment {
  const LiveComment({required this.id, required this.name, required this.body, required this.createdAt});

  final String id;
  final String name;
  final String body;
  final DateTime createdAt;

  factory LiveComment.fromMap(Map<String, dynamic> m) => LiveComment(
        id: m['id'] as String,
        name: (m['name'] as String?)?.trim() ?? '',
        body: (m['body'] as String?)?.trim() ?? '',
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// Extrait l'identifiant d'une vidéo YouTube (watch, youtu.be, shorts, live, embed).
String? parseYoutubeId(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  if (u == null || u.host.isEmpty) return null;
  final host = u.host.replaceFirst('www.', '').replaceFirst('m.', '');
  if (host == 'youtu.be') return u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    final v = u.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    final seg = u.pathSegments;
    if (seg.length >= 2 && const ['shorts', 'live', 'embed', 'v'].contains(seg[0])) return seg[1];
  }
  return null;
}
