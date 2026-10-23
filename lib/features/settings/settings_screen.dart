import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/history.dart';
import '../../data/models.dart';
import '../../data/search_history.dart';
import '../../data/settings.dart';
import '../../playback/equalizer.dart';
import '../../playback/loudness.dart';
import '../browse/history_screen.dart';
import '../player/equalizer_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final eq = ref.watch(equalizerProvider);
    final n = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(title, style: text.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          section('Apariencia'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(themeMode: v.first)),
            ),
          ),

          section('Descargas'),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('Calidad máxima de video'),
            subtitle: Text(s.maxVideoHeight == null ? 'La mejor disponible (hasta 1080p)' : '${s.maxVideoHeight}p'),
            onTap: () async {
              final picked = await _pick<int?>(
                context,
                'Calidad máxima',
                AppSettings.heights,
                (h) => h == null ? 'La mejor disponible' : '${h}p',
                s.maxVideoHeight,
              );
              if (picked != null) {
                await n.update((x) => picked.value == null ? x.copyWith(clearMaxHeight: true) : x.copyWith(maxVideoHeight: picked.value));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_present_outlined),
            title: const Text('Formato preferido'),
            subtitle: Text(s.preferredOutput.label),
            onTap: () async {
              final picked = await _pick<OutputKind>(context, 'Formato preferido', OutputKind.values, (k) => k.label, s.preferredOutput);
              if (picked?.value != null) await n.update((x) => x.copyWith(preferredOutput: picked!.value));
            },
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Calidad del MP3'),
            subtitle: Text('${s.mp3BitrateKbps} kbps'),
            onTap: () async {
              final picked = await _pick<int>(context, 'Calidad del MP3', AppSettings.mp3Bitrates, (k) => '$k kbps', s.mp3BitrateKbps);
              if (picked?.value != null) await n.update((x) => x.copyWith(mp3BitrateKbps: picked!.value));
            },
          ),
          ListTile(
            leading: const Icon(Icons.downloading_outlined),
            title: const Text('Descargas a la vez'),
            subtitle: Text('${s.maxConcurrentDownloads}'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                min: 1,
                max: 3,
                divisions: 2,
                value: s.maxConcurrentDownloads.toDouble(),
                label: '${s.maxConcurrentDownloads}',
                onChanged: (v) => n.update((x) => x.copyWith(maxConcurrentDownloads: v.round())),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Dónde se guardan'),
            subtitle: Text(Platform.isIOS
                ? 'App Archivos → En mi iPhone → Video Downloader'
                : 'Almacenamiento de la app; compártelos desde la Biblioteca para guardarlos en otra carpeta.'),
          ),

          section('Reproducción'),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next_outlined),
            title: const Text('Reproducción automática'),
            subtitle: const Text('Al terminar un video, pasa al siguiente de "A continuación".'),
            value: s.autoplayNext,
            onChanged: (v) => n.update((x) => x.copyWith(autoplayNext: v)),
          ),

          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: const Text('Ecualizador'),
            subtitle: Text(eq.enabled ? eq.preset.label : 'Apagado'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(EqualizerScreen.route()),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('Volumen parejo'),
            subtitle: Text(s.loudnessMode.description),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<LoudnessMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in LoudnessMode.values) ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {s.loudnessMode},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(loudnessMode: v.first)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.trending_up_rounded),
            title: const Text('Subir las canciones bajas'),
            subtitle: Text(Platform.isAndroid
                ? 'Además de bajar las fuertes, refuerza las que suenan bajito.'
                : 'Solo en Android: en iPhone el volumen de la app no puede pasar del original.'),
            value: Platform.isAndroid && s.boostQuiet,
            onChanged: Platform.isAndroid && s.loudnessMode != LoudnessMode.off
                ? (v) => n.update((x) => x.copyWith(boostQuiet: v))
                : null,
          ),

          section('Mixtape sin conexión'),
          SwitchListTile(
            secondary: const Icon(Icons.offline_bolt_outlined),
            title: const Text('Guardar lo que escucho'),
            subtitle: const Text('Lo que escuches más de 30 segundos se guarda para oírlo sin internet.'),
            value: s.mixtapeEnabled,
            onChanged: (v) => n.update((x) => x.copyWith(mixtapeEnabled: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Solo con Wi-Fi'),
            subtitle: const Text('Para no gastar datos móviles.'),
            value: s.mixtapeWifiOnly,
            onChanged: s.mixtapeEnabled ? (v) => n.update((x) => x.copyWith(mixtapeWifiOnly: v)) : null,
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Canciones máximas'),
            subtitle: Text('${s.mixtapeMax} (al pasarse se borran las más antiguas guardadas solas)'),
            enabled: s.mixtapeEnabled,
            onTap: () async {
              final picked = await _pick<int>(context, 'Canciones máximas', AppSettings.mixtapeSizes, (k) => '$k canciones', s.mixtapeMax);
              if (picked?.value != null) await n.update((x) => x.copyWith(mixtapeMax: picked!.value));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Vaciar el mixtape'),
            subtitle: const Text('Borra lo guardado solo. Tus descargas no se tocan.'),
            onTap: () async {
              final removed = await ref.read(downloadsProvider.notifier).clearMixtape();
              if (context.mounted) showMessage(context, removed == 0 ? 'El mixtape ya estaba vacío' : 'Se borraron $removed canciones del mixtape');
            },
          ),

          section('Historial'),
          SwitchListTile(
            secondary: const Icon(Icons.history),
            title: const Text('Guardar historial'),
            subtitle: const Text('Para "Seguir viendo", "Para ti" y las búsquedas recientes. Solo se guarda en este teléfono.'),
            value: s.saveHistory,
            onChanged: (v) => n.update((x) => x.copyWith(saveHistory: v)),
          ),
          ListTile(
            leading: const Icon(Icons.manage_history),
            title: const Text('Ver historial'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Borrar historial'),
            onTap: () async {
              await ref.read(historyProvider.notifier).clear();
              if (context.mounted) showMessage(context, 'Historial borrado');
            },
          ),
          ListTile(
            leading: const Icon(Icons.manage_search),
            title: const Text('Borrar búsquedas recientes'),
            onTap: () async {
              await ref.read(searchHistoryProvider.notifier).clear();
              if (context.mounted) showMessage(context, 'Búsquedas recientes borradas');
            },
          ),

          section('Acerca de'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Video Downloader'),
            subtitle: Text('Creado por Marco Yam · Powered by Claude\nUso personal. Descargar de YouTube va contra sus Términos de servicio.'),
            isThreeLine: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Diálogo de opciones. Devuelve null si se canceló; si no, un registro con el valor elegido
  /// (que puede ser null, p. ej. "la mejor calidad").
  static Future<({T value})?> _pick<T>(BuildContext context, String title, List<T> options, String Function(T) label, T current) {
    return showDialog<({T value})>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            ListTile(
              leading: Icon(o == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(label(o)),
              onTap: () => Navigator.pop(c, (value: o)),
            ),
        ],
      ),
    );
  }
}
