/// Reglas de "Tu biblioteca" (filtros, orden y colecciones), separadas para probarlas.
library;

import 'dart:io';

import '../../data/models.dart';

/// Un archivo descargado que existe en el teléfono.
typedef LibraryEntry = ({DownloadTask task, File file});

/// Chips de arriba (como Spotify). Sin chip = todas las colecciones.
enum LibraryChip {
  playlists('Listas'),
  folders('Carpetas'),
  artists('Artistas'),
  songs('Canciones'),
  videos('Videos');

  const LibraryChip(this.label);
  final String label;

  /// Muestra archivos (no colecciones).
  bool get showsFiles => this == songs || this == videos;
}

enum LibrarySort {
  recent('Recientes'),
  alpha('Alfabético'),
  creator('Creador');

  const LibrarySort(this.label);
  final String label;

  LibrarySort get next => LibrarySort.values[(index + 1) % LibrarySort.values.length];
}

enum CollectionKind { playlist, folder, artist }

/// Una fila de colección: lista, carpeta o artista.
typedef LibraryCollection = ({
  CollectionKind kind,
  int? id,
  String title,
  String subtitle,
  String creator,
  int recency,
  List<String> coverIds,
});

/// "1 canción" / "3 canciones" (o archivos).
String countLabel(int n, {String one = 'archivo', String many = 'archivos'}) => n == 1 ? '1 $one' : '$n $many';

/// Artista de un archivo: el canal/autor, sin " - Topic" ni "VEVO" (como aparecen en YouTube).
String artistOf(DownloadTask t) {
  var a = t.author.trim();
  if (a.isEmpty) return 'Desconocido';
  a = a.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
  a = a.replaceAll(RegExp(r'VEVO$'), '').trim();
  return a.isEmpty ? 'Desconocido' : a;
}

/// Agrupa por artista, de más archivos a menos (y alfabético en empate).
List<({String artist, List<LibraryEntry> items})> groupByArtist(List<LibraryEntry> entries) {
  final map = <String, List<LibraryEntry>>{};
  for (final e in entries) {
    map.putIfAbsent(artistOf(e.task), () => []).add(e);
  }
  final groups = [for (final kv in map.entries) (artist: kv.key, items: kv.value)]
    ..sort((a, b) {
      final byCount = b.items.length.compareTo(a.items.length);
      return byCount != 0 ? byCount : foldText(a.artist).compareTo(foldText(b.artist));
    });
  return groups;
}

/// Minúsculas y sin acentos, para buscar "cancion" y encontrar "Canción".
String foldText(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = s.toLowerCase().trim();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString();
}

/// ¿[text] coincide con la búsqueda [query]? (sin acentos ni mayúsculas; vacía = todo).
bool matchesQuery(String text, String query) {
  final q = foldText(query);
  return q.isEmpty || foldText(text).contains(q);
}

int _recencyOf(DownloadTask t) => t.completedAt ?? t.createdAt;

/// Archivos ordenados: recientes (lo último descargado primero), alfabético o por creador.
List<LibraryEntry> sortEntries(List<LibraryEntry> entries, LibrarySort sort) {
  final out = [...entries];
  switch (sort) {
    case LibrarySort.recent:
      out.sort((a, b) => _recencyOf(b.task).compareTo(_recencyOf(a.task)));
    case LibrarySort.alpha:
      out.sort((a, b) => foldText(a.task.title).compareTo(foldText(b.task.title)));
    case LibrarySort.creator:
      out.sort((a, b) {
        final byArtist = foldText(artistOf(a.task)).compareTo(foldText(artistOf(b.task)));
        return byArtist != 0 ? byArtist : foldText(a.task.title).compareTo(foldText(b.task.title));
      });
  }
  return out;
}

/// Colecciones ordenadas. Recientes: lo modificado o descargado más nuevo primero.
/// Creador: las tuyas (listas y carpetas) primero, luego artistas por nombre.
List<LibraryCollection> sortCollections(List<LibraryCollection> items, LibrarySort sort) {
  final out = [...items];
  switch (sort) {
    case LibrarySort.recent:
      out.sort((a, b) {
        final byTime = b.recency.compareTo(a.recency);
        return byTime != 0 ? byTime : foldText(a.title).compareTo(foldText(b.title));
      });
    case LibrarySort.alpha:
      out.sort((a, b) => foldText(a.title).compareTo(foldText(b.title)));
    case LibrarySort.creator:
      out.sort((a, b) {
        final byCreator = foldText(a.creator).compareTo(foldText(b.creator));
        return byCreator != 0 ? byCreator : foldText(a.title).compareTo(foldText(b.title));
      });
  }
  return out;
}

/// Colecciones de una carpeta: conteo y lo más reciente de sus archivos, y hasta 4 portadas.
LibraryCollection folderCollection(LibraryFolder f, List<LibraryEntry> files) {
  final recency = files.isEmpty ? 0 : files.map((e) => _recencyOf(e.task)).reduce((a, b) => a > b ? a : b);
  return (
    kind: CollectionKind.folder,
    id: f.id,
    title: f.name,
    subtitle: 'Carpeta · ${countLabel(files.length)}',
    creator: 'Tú',
    recency: recency,
    coverIds: [for (final e in files.take(4)) e.task.videoId],
  );
}

LibraryCollection artistCollection(String artist, List<LibraryEntry> files) => (
      kind: CollectionKind.artist,
      id: null,
      title: artist,
      subtitle: 'Artista · ${countLabel(files.length)}',
      creator: artist,
      recency: files.isEmpty ? 0 : files.map((e) => _recencyOf(e.task)).reduce((a, b) => a > b ? a : b),
      coverIds: [if (files.isNotEmpty) files.first.task.videoId],
    );

/// Qué colecciones mostrar según el chip: sin chip, listas y carpetas (los artistas tienen su
/// chip, como en Spotify); con chip, solo ese tipo. [query] filtra por nombre.
List<LibraryCollection> visibleCollections({
  required List<LibraryCollection> playlists,
  required List<LibraryCollection> folders,
  required List<LibraryCollection> artists,
  required LibraryChip? chip,
  required LibrarySort sort,
  String query = '',
}) {
  final pool = switch (chip) {
    null => [...playlists, ...folders, if (query.trim().isNotEmpty) ...artists],
    LibraryChip.playlists => playlists,
    LibraryChip.folders => folders,
    LibraryChip.artists => artists,
    LibraryChip.songs || LibraryChip.videos => const <LibraryCollection>[],
  };
  return sortCollections(pool.where((c) => matchesQuery(c.title, query)).toList(), sort);
}

/// Archivos visibles con el chip "Canciones"/"Videos" (o todos en una carpeta/artista/búsqueda).
List<LibraryEntry> visibleEntries(List<LibraryEntry> entries, {LibraryChip? chip, String query = '', required LibrarySort sort}) {
  final filtered = entries.where((e) {
    if (chip == LibraryChip.songs && !e.task.kind.isAudio) return false;
    if (chip == LibraryChip.videos && e.task.kind.isAudio) return false;
    return matchesQuery('${e.task.title} ${e.task.author}', query);
  }).toList();
  return sortEntries(filtered, sort);
}
