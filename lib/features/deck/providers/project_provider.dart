import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../settings/providers/settings_provider.dart';
import '../controller/deck_renderer.dart';
import '../controller/default_deck.dart';
import '../models/deck_model.dart';

final projectProvider = NotifierProvider<ProjectNotifier, DeckProject>(ProjectNotifier.new);

/// Which page and slot the editor has selected.
class EditorSelection {
  const EditorSelection({this.page = 0, this.section, this.slot});
  final int page;
  final int? section;
  final int? slot;
  bool get hasSlot => section != null && slot != null;
}

final selectionProvider = NotifierProvider<SelectionNotifier, EditorSelection>(SelectionNotifier.new);

class SelectionNotifier extends Notifier<EditorSelection> {
  @override
  EditorSelection build() => const EditorSelection();
  void page(int p) => state = EditorSelection(page: p);
  void slot(int section, int slot) => state = EditorSelection(page: state.page, section: section, slot: slot);
  void clearSlot() => state = EditorSelection(page: state.page);
}

class ProjectNotifier extends Notifier<DeckProject> {
  Timer? _saveTimer;
  bool _loaded = false;

  @override
  DeckProject build() {
    _load();
    // Placeholder until the saved project (or the default deck) is loaded.
    return DeckProject(pages: [DeckPage(id: newId(), sections: const [DeckSection(rows: 2, cols: 3, keys: [null, null, null, null, null, null])])]);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}project.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        state = DeckProject.fromJson(jsonDecode(await f.readAsString()));
      } else {
        state = await buildDefaultDeck(arabic: ref.read(settingsProvider).arabic);
      }
    } catch (e) {
      debugPrint('project load failed: $e');
    }
    _loaded = true;
  }

  void _save() {
    if (!_loaded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        await (await _file()).writeAsString(jsonEncode(state.toJson()));
      } catch (e) {
        debugPrint('project save failed: $e');
      }
    });
  }

  void replace(DeckProject p) {
    state = p;
    _save();
  }

  void update(DeckProject Function(DeckProject p) fn) => replace(fn(state));

  /// Adopts the screen size of the connected board. A deck designed for the
  /// other orientation gets its grids transposed, as when switching by hand.
  void setPanel(int width, int height) {
    if (width <= 0 || height <= 0 || (width == state.panelW && height == state.panelH)) return;
    final next = state.copyWith(panelW: width, panelH: height);
    final flip = isLandscape(next) != isLandscape(state);
    replace(next.copyWith(pages: flip ? _transposed(next.pages) : null));
  }

  static List<DeckPage> _transposed(List<DeckPage> pages) => [
        for (final p in pages) p.copyWith(sections: [for (final s in p.sections) s.copyWith(rows: s.cols, cols: s.rows)]),
      ];

  /// Switch portrait/landscape. Crossing between the two transposes every grid
  /// (3x2 becomes 2x3) so keys keep sensible proportions.
  void setRotation(int rotation) {
    final flip = rotation.isOdd != state.rotation.isOdd;
    var pages = state.pages;
    if (flip) pages = _transposed(pages);
    replace(state.copyWith(rotation: rotation, pages: pages));
  }

  Future<void> resetToDefault() async => replace(await buildDefaultDeck(arabic: ref.read(settingsProvider).arabic));

  // Pages
  void updatePage(int i, DeckPage Function(DeckPage p) fn) {
    final pages = [...state.pages];
    pages[i] = fn(pages[i]);
    replace(state.copyWith(pages: pages));
  }

  int addPage(String name) {
    final page = DeckPage(id: newId(), name: name, sections: const [
      DeckSection(rows: 3, cols: 3, keys: [null, null, null, null, null, null, null, null, null]),
    ]);
    replace(state.copyWith(pages: [...state.pages, page]));
    return state.pages.length - 1;
  }

  int duplicatePage(int i) {
    final src = state.pages[i];
    final copy = DeckPage.fromJson(jsonDecode(jsonEncode(src.toJson())));
    final fresh = copy.copyWith(
      sections: copy.sections
          .map((s) => s.copyWith(keys: s.keys.map((k) => k == null ? null : DeckKey.fromJson({...k.toJson(), 'id': newId()})).toList()))
          .toList(),
    );
    final pages = [...state.pages]..insert(i + 1, DeckPage.fromJson({...fresh.toJson(), 'id': newId()}));
    replace(state.copyWith(pages: pages));
    return i + 1;
  }

  void removePage(int i) {
    if (state.pages.length <= 1) return;
    replace(state.copyWith(pages: [...state.pages]..removeAt(i)));
  }

  void movePage(int from, int to) {
    final pages = [...state.pages];
    final p = pages.removeAt(from);
    pages.insert(to.clamp(0, pages.length), p);
    replace(state.copyWith(pages: pages));
  }

  // Sections
  void updateSection(int page, int section, DeckSection Function(DeckSection s) fn) {
    updatePage(page, (p) {
      final secs = [...p.sections];
      secs[section] = fn(secs[section]);
      return p.copyWith(sections: secs);
    });
  }

  void addSection(int page) => updatePage(
      page, (p) => p.copyWith(sections: [...p.sections, const DeckSection(rows: 1, cols: 3, keys: [null, null, null])]));

  void removeSection(int page, int section) =>
      updatePage(page, (p) => p.sections.length <= 1 ? p : p.copyWith(sections: [...p.sections]..removeAt(section)));

  void moveSection(int page, int section, int delta) => updatePage(page, (p) {
        final to = section + delta;
        if (to < 0 || to >= p.sections.length) return p;
        final secs = [...p.sections];
        final s = secs.removeAt(section);
        secs.insert(to, s);
        return p.copyWith(sections: secs);
      });

  // Keys
  void setKey(int page, int section, int slot, DeckKey? key) =>
      updateSection(page, section, (s) => s.copyWith(keys: [...s.keys]..[slot] = key));

  void updateKey(int page, int section, int slot, DeckKey Function(DeckKey k) fn) => updateSection(page, section, (s) {
        final k = s.keys[slot];
        if (k == null) return s;
        return s.copyWith(keys: [...s.keys]..[slot] = fn(k));
      });

  /// Swap two slots (drag and drop), possibly across sections.
  void swapSlots(int page, (int, int) a, (int, int) b) => updatePage(page, (p) {
        final secs = [for (final s in p.sections) s.copyWith(keys: [...s.keys])];
        final ka = secs[a.$1].keys[a.$2];
        secs[a.$1].keys[a.$2] = secs[b.$1].keys[b.$2];
        secs[b.$1].keys[b.$2] = ka;
        return p.copyWith(sections: secs);
      });
}
