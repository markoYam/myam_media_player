import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import 'format.dart';

/// Miniatura 16:9 con la duración en la esquina (estilo YouTube).
class VideoThumb extends StatelessWidget {
  const VideoThumb({super.key, required this.url, this.duration, this.isLive = false, this.radius = 12});

  final String url;
  final Duration? duration;
  final bool isLive;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
              errorWidget: (_, __, ___) => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.movie_outlined, color: scheme.onSurfaceVariant),
              ),
            ),
            if (isLive || duration != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isLive ? Colors.red.shade700 : Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Text(
                      isLive ? 'EN VIVO' : formatDuration(duration!),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta grande de video (miniatura arriba, título y metadatos abajo).
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.video, required this.onTap});

  final VideoSummary video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoThumb(url: video.thumbnailUrl, duration: video.duration, isLive: video.isLive),
            const SizedBox(height: 10),
            Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              [video.author, videoMeta(views: video.viewCount, uploaded: video.uploadedText)].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila compacta (miniatura a la izquierda): relacionados, biblioteca, descargas.
class CompactRow extends StatelessWidget {
  const CompactRow({
    super.key,
    required this.thumbnailUrl,
    required this.title,
    required this.subtitle,
    this.duration,
    this.onTap,
    this.trailing,
    this.bottom,
  });

  final String thumbnailUrl;
  final String title;
  final String subtitle;
  final Duration? duration;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: VideoThumb(url: thumbnailUrl, duration: duration, radius: 8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  if (bottom != null) ...[const SizedBox(height: 6), bottom!],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        title: 'Algo salió mal',
        message: message,
        action: onRetry == null ? null : FilledButton.tonal(onPressed: onRetry, child: const Text('Reintentar')),
      );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Índigo del ícono de la app.
const brandIndigo = Color(0xFF4F46E5);

/// Tema oscuro ya armado (reproductor y mini reproductor siempre van en oscuro).
final ThemeData darkAppTheme = buildTheme(Brightness.dark);

/// Fondo casi negro del tema oscuro (estilo OLED, como las apps de música).
const _ink = Color(0xFF0E0E12);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: brandIndigo, brightness: brightness);
  if (dark) {
    scheme = scheme.copyWith(
      surface: _ink,
      surfaceContainerLowest: const Color(0xFF09090C),
      surfaceContainerLow: const Color(0xFF141419),
      surfaceContainer: const Color(0xFF19191F),
      surfaceContainerHigh: const Color(0xFF212129),
      surfaceContainerHighest: const Color(0xFF2A2A33),
    );
  }
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final t = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    // Títulos con más peso: jerarquía clara como en Spotify / YouTube Music.
    textTheme: t.copyWith(
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF09090C) : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      height: 66,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(t.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.onSurface,
      labelStyle: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      secondaryLabelStyle: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.surface),
      checkmarkColor: scheme.surface,
      showCheckmark: false,
    ),
    cardTheme: const CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surfaceContainer, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
