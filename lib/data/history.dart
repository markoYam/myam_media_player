import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'database.dart';
import 'models.dart';
import 'settings.dart';

/// Historial de lo visto o escuchado en streaming. Solo en el teléfono; se guardan las últimas 500.
class HistoryNotifier extends Notifier<List<WatchHistoryEntry>> {
  static const maxEntries = 500;

  /// Si quedan menos de 15 s, se considera terminado y vuelve a 0 (no sale en "Seguir viendo").
  static const finishedMargin = Duration(seconds: 15);

  AppDatabase? _db;

  @override
  List<WatchHistoryEntry> build() {
    unawaited(_reload());
    return const [];
  }

  Future<AppDatabase> _database() async {
    final cached = _db;
    if (cached != null) return cached;
    final AppDatabase db = await ref.read(databaseProvider.future);
    return _db = db;
  }

  Future<void> _reload() async {
    state = await (await _database()).history(limit: maxEntries);
  }

  bool get _enabled => ref.read(settingsProvider).saveHistory;

  /// Registra (o sube al principio) un video al empezar a verlo; conserva la posición guardada.
  Future<void> record(VideoSummary v) async {
    if (!_enabled) return;
    final db = await _database();
    final previous = await db.historyEntry(v.id);
    await db.upsertHistory(WatchHistoryEntry(
      videoId: v.id,
      title: v.title,
      author: v.author,
      channelId: v.channelId,
      duration: v.duration ?? previous?.duration,
      position: previous?.position ?? Duration.zero,
      watchedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await db.trimHistory(maxEntries);
    await _reload();
  }

  /// Guarda dónde se quedó. Si terminó (o casi), vuelve a 0.
  Future<void> savePosition(String videoId, Duration position, Duration? duration) async {
    if (!_enabled) return;
    final finished = duration != null && duration > Duration.zero && duration - position < finishedMargin;
    final value = finished ? Duration.zero : position;
    await (await _database()).updatePosition(videoId, value.inMilliseconds);
    state = [
      for (final e in state)
        if (e.videoId == videoId)
          WatchHistoryEntry(
            videoId: e.videoId,
            title: e.title,
            author: e.author,
            channelId: e.channelId,
            duration: duration ?? e.duration,
            position: value,
            watchedAt: e.watchedAt,
          )
        else
          e,
    ];
  }

  Future<WatchHistoryEntry?> entry(String videoId) async => (await _database()).historyEntry(videoId);

  Future<void> remove(String videoId) async {
    await (await _database()).deleteHistory(videoId);
    state = state.where((e) => e.videoId != videoId).toList();
  }

  Future<void> clear() async {
    await (await _database()).clearHistory();
    state = const [];
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<WatchHistoryEntry>>(HistoryNotifier.new);

/// "Seguir viendo": lo que se dejó a medias.
final continueWatchingProvider = Provider<List<WatchHistoryEntry>>(
  (ref) => ref.watch(historyProvider).where((e) => e.isResumable).take(20).toList(),
);
