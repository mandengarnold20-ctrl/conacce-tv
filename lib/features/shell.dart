import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/brand.dart';
import '../core/widgets/responsive.dart';
import '../data/providers.dart';
import 'home_screen.dart';
import 'gallery_screen.dart';
import 'live_screen.dart';
import 'radio_screen.dart';
import 'sermons_screen.dart';
import 'works_screen.dart';

enum AppTab { home, tv, radio, sermons, gallery, works }

final currentTabProvider = StateProvider<AppTab>((ref) => AppTab.home);

/// Vidéo en grand (téléphone tourné sur la TV) : on cache les menus.
final immersiveProvider = StateProvider<bool>((ref) => false);

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
            child: SafeArea(
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
  static const _pages = [HomeScreen(), LiveScreen(), RadioScreen(), SermonsScreen(), GalleryScreen(), WorksScreen()];

  @override
  void initState() {
    super.initState();
    Analytics.visit();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(currentTabProvider);
    final isLive = ref.watch(liveStreamProvider).valueOrNull?.canPlay ?? false;
    void select(int i) => ref.read(currentTabProvider.notifier).state = AppTab.values[i];

    Widget badge(IconData icon) => Badge(isLabelVisible: isLive, backgroundColor: AppColors.live, smallSize: 8, child: Icon(icon));
    final items = <(Widget, String)>[
      (const Icon(Icons.home_rounded), 'Accueil'),
      (badge(Icons.live_tv_rounded), 'TV'),
      (const Icon(Icons.radio_rounded), 'Radio'),
      (const Icon(Icons.video_library_rounded), 'Vidéos'),
      (const Icon(Icons.photo_library_rounded), 'Galerie'),
      (const Icon(Icons.menu_book_rounded), 'Œuvres'),
    ];
    final body = WaveBackground(child: IndexedStack(index: tab.index, children: _pages));
    final immersive = ref.watch(immersiveProvider);
    final wide = Breakpoints.isWide(context);

    // La zone des pages garde toujours la même place dans l'arbre (clé) :
    // tourner le téléphone ne recrée pas la vidéo en cours.
    return Scaffold(
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
  }
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
    // Jusqu'à 5 onglets visibles d'un coup ; au-delà, on fait glisser la barre.
    final itemWidth = width / (widget.items.length < 5 ? widget.items.length : 5.4);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00080F43), Color(0xD9080F43), AppColors.navyDeep], stops: [0, .35, 1]),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.items.length,
            itemBuilder: (context, i) {
              final (icon, label) = widget.items[i];
              final selected = i == widget.selected;
              return SizedBox(
                key: _key(i),
                width: itemWidth,
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: label,
                  child: InkResponse(
                    onTap: () => widget.onSelect(i),
                    radius: 36,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 54,
                        height: 30,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.sunYellow : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconTheme(data: IconThemeData(size: 22, color: selected ? AppColors.navy : AppColors.muted), child: Center(child: icon)),
                      ),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? AppColors.sunYellow : AppColors.muted,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          )),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
