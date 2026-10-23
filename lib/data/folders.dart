import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'database.dart';
import 'models.dart';
import 'youtube_service.dart';

const maxFolderName = 60;

String normalizeFolderName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// null si el nombre es válido; si no, el motivo.
String? folderNameError(String raw, Iterable<String> existingNames) {
  final name = normalizeFolderName(raw);
  if (name.isEmpty) return 'Escribe un nombre.';
  if (name.length > maxFolderName) return 'Máximo $maxFolderName caracteres.';
  if (existingNames.any((n) => n.toLowerCase() == name.toLowerCase())) return 'Ya existe una carpeta con ese nombre.';
  return null;
}

class FoldersState {
  const FoldersState({this.folders = const [], this.memberships = const {}});
  final List<LibraryFolder> folders;

  /// downloadId → ids de sus carpetas.
  final Map<int, Set<int>> memberships;

  int countOf(int folderId) => memberships.values.where((s) => s.contains(folderId)).length;
  Set<int> foldersOf(int downloadId) => memberships[downloadId] ?? const {};
  List<String> namesOf(int downloadId) {
    final ids = foldersOf(downloadId);
    return [for (final f in folders) if (ids.contains(f.id)) f.name];
  }
}

/// Carpetas de la biblioteca: un archivo puede estar en varias ("Agregar") o pasar de una a otra
/// ("Mover"). Son una organización dentro de la app: el archivo no cambia de lugar en el teléfono.
class FoldersNotifier extends Notifier<FoldersState> {
  AppDatabase? _db;

  @override
  FoldersState build() {
    unawaited(_reload());
    return const FoldersState();
  }

  Future<AppDatabase> _database() async {
    final cached = _db;
    if (cached != null) return cached;
    final AppDatabase db = await ref.read(databaseProvider.future);
    return _db = db;
  }

  Future<void> _reload() async {
    final db = await _database();
    state = FoldersState(folders: await db.folders(), memberships: await db.memberships());
  }

  /// Crea la carpeta y devuelve su id. Lanza [AppException] si el nombre no sirve.
  Future<int> create(String raw) async {
    final error = folderNameError(raw, state.folders.map((f) => f.name));
    if (error != null) throw AppException(error);
    final id = await (await _database()).createFolder(normalizeFolderName(raw));
    await _reload();
    return id;
  }

  Future<void> rename(int id, String raw) async {
    final error = folderNameError(raw, state.folders.where((f) => f.id != id).map((f) => f.name));
    if (error != null) throw AppException(error);
    await (await _database()).renameFolder(id, normalizeFolderName(raw));
    await _reload();
  }

  Future<void> delete(int id) async {
    await (await _database()).deleteFolder(id);
    await _reload();
  }

  Future<void> add(int folderId, Iterable<int> downloadIds) async {
    await (await _database()).addToFolder(folderId, downloadIds);
    await _reload();
  }

  Future<void> move(Iterable<int> downloadIds, {int? fromFolderId, required int toFolderId}) async {
    if (fromFolderId == toFolderId) return;
    await (await _database()).moveToFolder(downloadIds, fromFolderId: fromFolderId, toFolderId: toFolderId);
    await _reload();
  }

  Future<void> remove(int folderId, Iterable<int> downloadIds) async {
    await (await _database()).removeFromFolder(folderId, downloadIds);
    await _reload();
  }

  /// Tras borrar una descarga (la base ya borra sus pertenencias en cascada).
  Future<void> refresh() => _reload();
}

final foldersProvider = NotifierProvider<FoldersNotifier, FoldersState>(FoldersNotifier.new);
