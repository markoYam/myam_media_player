import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/art_colors.dart';
import 'mixtape.dart';

/// Portadas de una colección: 0 → ícono; 1 a 3 → la primera completa; 4+ → mosaico 2×2.
/// Usa las portadas guardadas en el teléfono (funciona sin internet).
class CoverMosaic extends StatelessWidget {
  const CoverMosaic({
    super.key,
    required this.videoIds,
    required this.size,
    this.radius = 6,
    this.circle = false,
    this.icon = Icons.folder_rounded,
    this.fallbackUrls = const {},
  });

  final List<String> videoIds;
  final double size;
  final double radius;

  /// Redonda (artistas, como en Spotify).
  final bool circle;
  final IconData icon;

  /// Miniatura de internet por videoId cuando no hay portada guardada (enlaces directos).
  final Map<String, String> fallbackUrls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cover(String id) => LocalCover(videoId: id, radius: 0, fallbackUrl: fallbackUrls[id]);
    final Widget child;
    if (videoIds.isEmpty) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(child: Icon(icon, size: size * 0.42, color: scheme.onSurfaceVariant)),
      );
    } else if (videoIds.length < 4 || circle) {
      child = cover(videoIds.first);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var col = 0; col < 2; col++) Expanded(child: SizedBox.expand(child: cover(videoIds[row * 2 + col])))],
              ),
            ),
        ],
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: circle ? ClipOval(child: child) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

/// Cabecera de una colección (carpeta, artista, mixtape), como en Spotify: fondo degradado con el
/// color de la portada, portada grande, título, detalle y botones de aleatorio y reproducir.
class CollectionHeader extends ConsumerWidget {
  const CollectionHeader({
    super.key,
    required this.art,
    required this.title,
    required this.subtitle,
    this.toneVideoId,
    this.tone,
    this.onPlay,
    this.onShuffle,
    this.actions = const [],
  });

  final Widget art;
  final String title;
  final String subtitle;

  /// Portada de la que se toma el color del fondo (o [tone] fijo).
  final String? toneVideoId;
  final Color? tone;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// Botones extra a la izquierda (p. ej. descargar).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final id = toneVideoId;
    final fromArt = id == null ? null : ref.watch(artToneProvider('https://i.ytimg.com/vi/$id/hqdefault.jpg')).value;
    final top = tone ?? fromArt ?? scheme.surfaceContainerHighest;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, scheme.surface]),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 10))]),
              child: art,
            ),
          ),
          const SizedBox(height: 16),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.headlineSmall),
          const SizedBox(height: 4),
          Text(subtitle, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              ...actions,
              const Spacer(),
              if (onShuffle != null)
                IconButton(tooltip: 'Aleatorio', iconSize: 28, icon: const Icon(Icons.shuffle_rounded), onPressed: onShuffle),
              const SizedBox(width: 8),
              if (onPlay != null) BigPlayButton(onPressed: onPlay!),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón redondo grande de reproducir (color principal, como el verde de Spotify).
class BigPlayButton extends StatelessWidget {
  const BigPlayButton({super.key, required this.onPressed, this.size = 56});
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Reproducir',
      child: Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.play_arrow_rounded, size: size * 0.6, color: scheme.onPrimary),
          ),
        ),
      ),
    );
  }
}
