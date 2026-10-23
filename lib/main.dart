import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'features/watch/watch_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La app va en vertical; solo el video a pantalla completa gira a horizontal.
  await SystemChrome.setPreferredOrientations(appOrientations);
  // Notificación multimedia, pantalla de bloqueo y audífonos (Android e iOS).
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.marcoyam.videodownloader.playback',
    androidNotificationChannelName: 'Reproducción',
    androidNotificationIcon: 'mipmap/ic_launcher',
  );
  runApp(const ProviderScope(child: VideoDownloaderApp()));
}
