import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'core/widgets.dart';
import 'data/download_manager.dart';
import 'data/settings.dart';
import 'features/browse/home_screen.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/library/library_screen.dart';
import 'features/links/link_router.dart';
import 'features/player/player_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_overlay.dart';
import 'platform/incoming_links.dart';
import 'playback/pip.dart';
import 'playback/video_session.dart';

class VideoDownloaderApp extends ConsumerStatefulWidget {
  const VideoDownloaderApp({super.key});

  @override
  ConsumerState<VideoDownloaderApp> createState() => _VideoDownloaderAppState();
}

class _VideoDownloaderAppState extends ConsumerState<VideoDownloaderApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: 'Video Downloader',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: const HomeShell(),
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          // Android en imagen en imagen: la ventanita muestra solo el video.
          const _PipVideoOverlay(),
          if (_showSplash) SplashOverlay(onFinished: () => setState(() => _showSplash = false)),
        ],
      ),
    );
  }
}

/// Pestañas principales con el mini reproductor encima de la barra de navegación.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<String>? _links;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Enlaces de "Compartir" (Android e iOS) y del esquema videodownloader://.
    _links = ref.read(incomingLinksProvider).links.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_links?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkClipboard());
  }

  Future<void> _open(String link) async {
    if (!mounted) return;
    final handled = await openLink(context, ref, link);
    if (!handled && mounted) showMessage(context, 'No reconozco ese enlace: $link');
  }

  /// iOS: si la extensión "Compartir" no pudo abrir la app, dejó el enlace copiado; se ofrece abrirlo.
  Future<void> _checkClipboard() async {
    if (!Platform.isIOS || !mounted) return;
    final links = ref.read(incomingLinksProvider);
    if (!await links.hasSharedClipboardLink() || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Compartiste un enlace con Video Downloader.'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () async {
            final link = await links.takeSharedClipboardLink();
            if (link != null) await _open(link);
          },
        ),
      ));
  }

  static const _pages = [HomeScreen(), SearchScreen(), DownloadsScreen(), LibraryScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    // Arranca el gestor de descargas al abrir la app (reanuda lo pendiente).
    final active = ref.watch(downloadsProvider.select((l) => l.where((t) => t.isActive).length));
    return Scaffold(
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
              const NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
              NavigationDestination(
                icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.download_outlined)),
                selectedIcon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.download)),
                label: 'Descargas',
              ),
              const NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: 'Biblioteca',
              ),
              const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Android en imagen en imagen: encima de todo, solo el video que se está viendo (la ventanita es
/// la app entera encogida, y los botones no caben ni se pueden tocar).
class _PipVideoOverlay extends ConsumerWidget {
  const _PipVideoOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inPip = ref.watch(pipModeProvider).value ?? false;
    if (!inPip) return const SizedBox.shrink();
    final session = ref.watch(videoSessionProvider);
    final c = (session?.isReady ?? false) ? session!.controller : null;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: c == null ? null : Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
      ),
    );
  }
}
