import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../playback/equalizer.dart';

/// Ecualizador: interruptor, curva, una barra vertical por banda y presets.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const EqualizerScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equalizerProvider);
    final n = ref.read(equalizerProvider.notifier);
    return Theme(
      data: darkAppTheme,
      child: Builder(builder: (context) {
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        const muted = Color(0xCCFFFFFF);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ecualizador'),
            actions: [
              Semantics(
                label: 'Ecualizador ${eq.enabled ? 'encendido' : 'apagado'}',
                child: Switch(value: eq.enabled, onChanged: n.setEnabled),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (!eq.ready)
                Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Reproduce una canción y vuelve aquí: el teléfono da sus bandas cuando el reproductor ya está sonando.'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // Curva de vista previa (atenuada si está apagado).
                AnimatedOpacity(
                  opacity: eq.enabled ? 1 : 0.35,
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
                  child: SizedBox(
                    height: 96,
                    child: CustomPaint(
                      painter: _CurvePainter(
                        gains: [for (final b in eq.bands) b.gain],
                        minDb: eq.minDb,
                        maxDb: eq.maxDb,
                        color: scheme.primary,
                        grid: Colors.white12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (var i = 0; i < eq.bands.length; i++)
                        _BandSlider(
                          band: eq.bands[i],
                          minDb: eq.minDb,
                          maxDb: eq.maxDb,
                          enabled: eq.enabled,
                          onChanged: (g) => n.setBandGain(i, g),
                          onChangeEnd: (_) => n.commit(),
                        ),
                    ],
                  ),
                ),
                if (!eq.enabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Enciende el ecualizador o elige un preset para ajustar.', textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: muted)),
                  ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Presets', style: text.titleMedium)),
                  TextButton.icon(
                    onPressed: eq.ready ? n.reset : null,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Restablecer'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in EqPreset.values)
                    if (p != EqPreset.custom || eq.custom.isNotEmpty)
                      ChoiceChip(
                        label: Text(p.label),
                        selected: eq.enabled && eq.preset == p,
                        onSelected: eq.ready ? (_) => n.selectPreset(p) : null,
                      ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                Platform.isAndroid
                    ? 'Usa el ecualizador de tu teléfono. Se aplica a la música de la app (no a los videos).'
                    : 'Se aplica a la música de la app: streaming, mixtape y descargas (no a los videos).',
                style: text.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Barra vertical de una banda: ganancia arriba, frecuencia abajo.
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.minDb,
    required this.maxDb,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final EqBand band;
  final double minDb;
  final double maxDb;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const muted = Color(0xCCFFFFFF);
    return SizedBox(
      width: 48,
      child: Column(
        children: [
          Text(formatGain(band.gain), maxLines: 1, style: text.labelSmall?.copyWith(color: muted)),
          Expanded(
            child: Semantics(
              label: formatFrequency(band.frequency),
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                  ),
                  child: Slider(
                    min: minDb,
                    max: maxDb,
                    divisions: ((maxDb - minDb) * 2).round(),
                    value: band.gain.clamp(minDb, maxDb).toDouble(),
                    semanticFormatterCallback: formatGain,
                    onChanged: enabled ? onChanged : null,
                    onChangeEnd: enabled ? onChangeEnd : null,
                  ),
                ),
              ),
            ),
          ),
          Text(formatFrequency(band.frequency), maxLines: 1, style: text.labelSmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

/// Curva suave que une las ganancias, con relleno degradado y la línea de 0 dB.
class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.gains, required this.minDb, required this.maxDb, required this.color, required this.grid});
  final List<double> gains;
  final double minDb;
  final double maxDb;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (gains.isEmpty) return;
    double y(double g) => size.height * (1 - (g - minDb) / (maxDb - minDb));
    final zero = y(0);
    canvas.drawLine(Offset(0, zero), Offset(size.width, zero), Paint()..color = grid..strokeWidth = 1);

    final step = gains.length > 1 ? size.width / (gains.length - 1) : 0.0;
    final pts = [for (var i = 0; i < gains.length; i++) Offset(gains.length > 1 ? i * step : size.width / 2, y(gains[i]))];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.color != color || old.minDb != minDb || old.maxDb != maxDb || !_sameList(old.gains, gains);

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
