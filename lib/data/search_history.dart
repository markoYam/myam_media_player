import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// Búsquedas recientes (solo en este teléfono), como las de YouTube.
const maxRecentSearches = 20;

/// Texto para comparar sin acentos ni mayúsculas: "Maná" = "mana".
String foldSearch(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final lower = text.toLowerCase().trim();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i >= 0 ? to[i] : ch);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// [query] al principio de [recents], sin repetidos (ignorando acentos y mayúsculas) y con un
/// máximo de [max]. Las vacías no se guardan.
List<String> addRecentSearch(List<String> recents, String query, {int max = maxRecentSearches}) {
  final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (q.isEmpty) return recents;
  final key = foldSearch(q);
  return [q, ...recents.where((r) => foldSearch(r) != key)].take(max).toList();
}

/// Recientes que empiezan con lo escrito (o lo contienen como palabra), para mostrarlas mientras
/// escribes; con el campo vacío, todas.
List<String> matchingRecents(List<String> recents, String typed, {int limit = 8}) {
  final t = foldSearch(typed);
  if (t.isEmpty) return recents;
  return recents.where((r) {
    final f = foldSearch(r);
    return f.startsWith(t) || f.contains(' $t');
  }).take(limit).toList();
}

class SearchHistoryNotifier extends Notifier<List<String>> {
  static const _key = 'search_history';

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getStringList(_key) ?? const [];
    if (ref.mounted) state = saved.take(maxRecentSearches).toList();
  }

  /// Guarda [query] si el ajuste "Guardar historial" está encendido.
  Future<void> add(String query) async {
    if (!ref.read(settingsProvider).saveHistory) return;
    state = addRecentSearch(state, query);
    await _persist();
  }

  Future<void> remove(String query) async {
    state = state.where((r) => r != query).toList();
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, state);
  }
}

final searchHistoryProvider = NotifierProvider<SearchHistoryNotifier, List<String>>(SearchHistoryNotifier.new);
