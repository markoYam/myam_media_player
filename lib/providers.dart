import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/youtube_service.dart';

/// Servicio de YouTube único para toda la app.
final youtubeServiceProvider = Provider<YouTubeService>((ref) {
  final service = YouTubeService();
  ref.onDispose(service.close);
  return service;
});

/// Base de datos abierta una sola vez.
final databaseProvider = FutureProvider<AppDatabase>((ref) => AppDatabase.open());
