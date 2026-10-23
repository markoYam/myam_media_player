import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets.dart';

/// Pantalla de bienvenida con créditos. Se dibuja encima de la app (que carga detrás), dura
/// ~1.6 s y se desvanece; tocarla la cierra antes.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onFinished});
  final VoidCallback onFinished;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final AnimationController _outro = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<double> _iconScale = Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _intro, curve: Curves.elasticOut));
  late final Animation<double> _content = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.65, curve: Curves.easeOut));
  late final Animation<double> _credits = CurvedAnimation(parent: _intro, curve: const Interval(0.35, 1, curve: Curves.easeOut));
  Timer? _hold;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _intro.forward().whenComplete(() => _hold = Timer(const Duration(milliseconds: 850), _close));
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _hold?.cancel();
    await _outro.forward();
    widget.onFinished();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _intro.dispose();
    _outro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return FadeTransition(
      opacity: ReverseAnimation(_outro),
      child: GestureDetector(
        onTap: _close,
        child: Semantics(
          label: 'Video Downloader. Creado por Marco Yam. Powered by Claude.',
          child: ColoredBox(
            color: scheme.surface,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: FadeTransition(
                      opacity: _content,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScaleTransition(
                            scale: _iconScale,
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(color: brandIndigo, borderRadius: BorderRadius.circular(30)),
                              child: const Icon(Icons.download_for_offline_outlined, color: Colors.white, size: 60),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Video Downloader', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: FadeTransition(
                        opacity: _credits,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Creado por Marco Yam', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              'Powered by Claude',
                              style: text.labelLarge?.copyWith(letterSpacing: 1, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
