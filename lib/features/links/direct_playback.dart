import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/widgets.dart';
import '../../data/download_manager.dart';
import '../../data/models.dart';
import '../../data/youtube_service.dart' show AppException;
import '../../playback/audio_controller.dart';
import '../../playback/video_session.dart';
import '../player/player_screen.dart';
import '../watch/watch_screen.dart' show FullscreenVideo, VideoSurface;

/// Un audio o video de un enlace directo (Internet Archive o un archivo suelto).
typedef DirectMedia = ({String id, String title, String author, Uri url, Uri? art});

/// Reproduce [items] (audios) desde [index] y abre el reproductor de música.
Future<void> playDirectAudio(BuildContext context, WidgetRef ref, List<DirectMedia> items, int index) async {
  try {
    ref.read(videoSessionProvider.notifier).close();
    await ref.read(audioControllerProvider).playDirect(items, startIndex: index);
    if (context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const PlayerScreen()));
    }
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Abre un video de un enlace directo a pantalla completa (pausa la música y el video de YouTube).
Future<void> openDirectVideo(BuildContext context, WidgetRef ref, {required Uri url, required String title}) async {
  ref.read(videoSessionProvider.notifier).close();
  await ref.read(audioControllerProvider).player.pause();
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DirectVideoScreen(url: url, title: title)));
}

/// Encola la descarga de un enlace directo y avisa.
Future<void> downloadDirect(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String title,
  required String author,
  required Uri url,
  required OutputKind kind,
  String? thumbnail,
  int? sizeBytes,
  String? qualityLabel,
}) async {
  try {
    await ref.read(downloadsProvider.notifier).enqueueDirect(
          id: id,
          title: title,
          author: author,
          url: url,
          kind: kind,
          thumbnail: thumbnail,
          sizeBytes: sizeBytes,
          qualityLabel: qualityLabel,
        );
    if (context.mounted) showMessage(context, 'Descarga agregada. Mírala en la pestaña Descargas.');
  } on AppException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  }
}

/// Video de un enlace directo, con los mismos controles que "ver video" y pantalla completa.
class DirectVideoScreen extends StatefulWidget {
  const DirectVideoScreen({super.key, required this.url, required this.title});
  final Uri url;
  final String title;

  @override
  State<DirectVideoScreen> createState() => _DirectVideoScreenState();
}

class _DirectVideoScreenState extends State<DirectVideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(widget.url);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_failed) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No se pudo reproducir este video. Prueba descargarlo.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
      );
    } else if (!_c.value.isInitialized) {
      body = const CircularProgressIndicator();
    } else {
      body = AspectRatio(
        aspectRatio: 16 / 9,
        child: VideoSurface(
          controller: _c,
          onFullscreen: () => Navigator.of(context).push(PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => FullscreenVideo(controller: _c),
            transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
          )),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(child: body),
    );
  }
}
