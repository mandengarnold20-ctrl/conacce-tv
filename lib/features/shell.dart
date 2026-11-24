import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/device.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/providers.dart';
import 'home_screen.dart';
import 'comments_screen.dart';
import 'contact_screen.dart';
import 'live_screen.dart';
import 'org_screen.dart';
import 'radio_screen.dart';
import 'sermons_screen.dart';
import 'works_screen.dart';
import 'worship_screen.dart';

/// Menu de l'appli : Accueil, TV, Radio, Commentaires, CCA, CIU, Audio, Œuvres, Vidéos (cultes), Contact.
enum AppTab { home, tv, radio, comments, cca, ciu, audio, works, videos, contact }

final currentTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

/// Vidéo en grand (téléphone tourné sur la TV) : on cache les menus.
final immersiveProvider = StateProvider<bool>((ref) => false);

/// Téléviseur : demande de remettre la chaîne en plein écran (on choisit « TV » dans le menu).
final tvFullscreenProvider = StateProvider<int>((ref) => 0);

/// Écran de démarrage : le logo Conacce TV et sa lumière.
/// Toucher l'écran ouvre l'accueil.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  void _enter(BuildContext context) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) => const AppShell(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        button: true,
        label: 'Entrer dans l’appli',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _enter(context),
          child: WaveBackground(
            child: Stack(fit: StackFit.expand, children: [
              const IgnorePointer(child: ConacceWatermark()),
              SafeArea(
              child: SizedBox.expand(
                child: Column(
                  children: [
                    const Spacer(flex: 5),
                    const LogoShine(width: 300, radius: 8),
                    const SizedBox(height: 20),
                    Text('TÉLÉVISION · RADIO · CULTES · ŒUVRES D’OR',
                        textAlign: TextAlign.center,
                        style: AppTheme.title(size: 11, weight: FontWeight.w500, color: AppColors.mist).copyWith(letterSpacing: 2.5)),
                    const Spacer(flex: 4),
                    const _TapHint(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TapHint extends StatefulWidget {
  const _TapHint();

  @override
  State<_TapHint> createState() => _TapHintState();
}

class _TapHintState extends State<_TapHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .45, end: 1.0).animate(_c),
        child: const Text('Touchez l’écran pour entrer', style: TextStyle(color: AppColors.mist, fontSize: 13)),
      );
}

/// Coquille : les onglets (la barre du bas défile au doigt quand ils sont nombreux). Téléphone : barre en bas. Tablette / ordinateur / TV : menu à gauche.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _pages = [HomeScreen(), LiveScreen(), RadioScreen(), CommentsScreen(), OrgScreen.cca(), OrgScreen.ciu(), WorshipScreen.audio(), WorksScreen(), SermonsScreen.cultes(), ContactScreen(asTab: true)];

  @override
  void initState() {
    super.initState();
    Analytics.visit();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(currentTabProvider);
    final isLive = ref.watch(liveStreamProvider).valueOrNull?.canPlay ?? false;
    void select(int i) {
      ref.read(currentTabProvider.notifier).state = AppTab.values[i];
      // Téléviseur : choisir « TV » remet la chaîne en plein écran.
      if (isTvDevice && AppTab.values[i] == AppTab.tv) ref.read(tvFullscreenProvider.notifier).state++;
    }

    Widget badge(IconData icon) => Badge(isLabelVisible: isLive, backgroundColor: AppColors.live, smallSize: 8, child: Icon(icon));
    // Icônes fines (au trait), comme une appli moderne ; l'onglet choisi s'allume en jaune.
    final items = <(Widget, String)>[
      (const Icon(Icons.home_outlined), 'Accueil'),
      (badge(Icons.live_tv_outlined), 'TV'),
      (const Icon(Icons.radio_outlined), 'Radio'),
      (const Icon(Icons.forum_outlined), 'Commentaires'),
      (const Icon(Icons.public_outlined), 'CCA'),
      (const Icon(Icons.school_outlined), 'CIU'),
      (const Icon(Icons.headphones_outlined), 'Audio'),
      (const Icon(Icons.menu_book_outlined), 'Œuvres'),
      (const Icon(Icons.video_library_outlined), 'Vidéos'),
      (const Icon(Icons.mail_outline_rounded), 'Contact'),
    ];
    // Filigrane du logo CONACCE Chaplains : seulement sur les pages qui parlent de la Conacce.
    final showMark = switch (tab) {
      AppTab.home || AppTab.tv || AppTab.contact => true,
      AppTab.cca => true,
      _ => false,
    };
    final body = WaveBackground(
      child: Stack(fit: StackFit.expand, children: [
        IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 500),
            opacity: showMark ? 1 : 0,
            child: const ConacceWatermark(),
          ),
        ),
        IndexedStack(index: tab.index, children: _pages),
      ]),
    );
    final immersive = ref.watch(immersiveProvider);
    final wide = Breakpoints.isWide(context);

    // La zone des pages garde toujours la même place dans l'arbre (clé) :
    // tourner le téléphone ne recrée pas la vidéo en cours.
    final scaffold = Scaffold(
      extendBody: true,
      body: Row(children: [
        if (wide && !immersive)
          Container(
            key: const ValueKey('rail'),
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.navy, AppColors.navyDeep])),
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: tab.index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.sunYellow,
              leading: const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: LogoShine(width: 120, radius: 3)),
              selectedIconTheme: const IconThemeData(color: AppColors.navy),
              unselectedIconTheme: const IconThemeData(color: AppColors.muted),
              selectedLabelTextStyle: const TextStyle(color: AppColors.sunYellow, fontWeight: FontWeight.w700, fontSize: 12),
              unselectedLabelTextStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
              destinations: [for (final (icon, label) in items) NavigationRailDestination(icon: icon, label: Text(label))],
            ),
          ),
        Expanded(key: const ValueKey('pages'), child: body),
      ]),
      bottomNavigationBar: wide || immersive
          ? null
          : _ScrollNavBar(items: items, selected: tab.index, onSelect: select),
    );
    if (!isTvDevice) return scaffold;
    // Téléviseur : Retour depuis le menu = retour à la chaîne ; sur la chaîne, deux fois Retour = quitter.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || ref.read(immersiveProvider)) return; // la chaîne en plein écran gère elle-même Retour
        if (tab != AppTab.tv) {
          select(AppTab.tv.index);
          return;
        }
        final t = DateTime.now();
        if (_lastBack != null && t.difference(_lastBack!) < const Duration(seconds: 3)) {
          SystemNavigator.pop();
          return;
        }
        _lastBack = t;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 3),
          content: Text('Appuyez encore sur Retour pour quitter Conacce TV'),
        ));
      },
      child: scaffold,
    );
  }

  DateTime? _lastBack;
}

/// Barre du bas qui défile au doigt : on peut ajouter autant d'onglets que l'on veut.
class _ScrollNavBar extends StatefulWidget {
  const _ScrollNavBar({required this.items, required this.selected, required this.onSelect});

  final List<(Widget, String)> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<_ScrollNavBar> createState() => _ScrollNavBarState();
}

class _ScrollNavBarState extends State<_ScrollNavBar> {
  final _keys = <int, GlobalKey>{};

  GlobalKey _key(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  @override
  void didUpdateWidget(_ScrollNavBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      // L'onglet choisi vient se placer bien en vue.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _key(widget.selected).currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Barre flottante arrondie : 5 onglets visibles, on glisse au doigt pour les autres.
    const margin = 14.0;
    final inner = width - margin * 2 - 8;
    final itemWidth = inner / (widget.items.length <= 5 ? widget.items.length : 5.4);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: margin),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xF20A1150),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0x26FFFFFF)),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.items.length,
              itemBuilder: (context, i) {
                final (icon, label) = widget.items[i];
                final selected = i == widget.selected;
                final color = selected ? AppColors.sunYellow : const Color(0xFFC9D2F5);
                return SizedBox(
                  key: _key(i),
                  width: itemWidth,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: label,
                    child: InkResponse(
                      onTap: () => widget.onSelect(i),
                      radius: 34,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          scale: selected ? 1.12 : 1,
                          child: IconTheme(data: IconThemeData(size: 24, color: color), child: icon),
                        ),
                        const SizedBox(height: 5),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(fontSize: 10.5, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo CONACCE Chaplains en filigrane, très discret, comme sur un papier à en-tête :
/// grand et centré, sans changer le fond.
class ConacceWatermark extends StatelessWidget {
  const ConacceWatermark({super.key});

  // Gris clair (le logo garde ses détails mais perd ses couleurs).
  static const _greyscale = ColorFilter.matrix([
    0.30, 0.59, 0.11, 0, 40,
    0.30, 0.59, 0.11, 0, 40,
    0.30, 0.59, 0.11, 0, 60,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Proportionnel à l'écran (jamais coupé), centré horizontalement et placé
      // un peu plus bas que le milieu : sous la TV / le grand écran de l'accueil.
      final size = [c.maxWidth * .9, c.maxHeight * .52, 640.0].reduce((a, b) => a < b ? a : b);
      return Align(
        alignment: const Alignment(0, .32),
        child: SizedBox(
          width: size,
          height: size,
          child: Opacity(
            opacity: .045,
            child: ColorFiltered(
              colorFilter: _greyscale,
              child: Image.asset('assets/images/conacce_chaplains.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
          ),
        ),
      );
    });
  }
}
