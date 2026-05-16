import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/media_item.dart';
import 'providers.dart';

class LibraryState {
  const LibraryState({this.items = const [], this.loading = false});

  final List<MediaItem> items;
  final bool loading;

  LibraryState copyWith({List<MediaItem>? items, bool? loading}) {
    return LibraryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
    );
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController(this._ref) : super(const LibraryState()) {
    refresh();
  }

  final Ref _ref;

  Future<void> refresh() async {
    state = state.copyWith(loading: true);
    try {
      final lib = await _ref.read(mediaLibraryProvider.future);
      final sorted = [...lib.items]
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
      state = LibraryState(items: sorted, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final lib = await _ref.read(mediaLibraryProvider.future);
    await lib.remove(id, deleteFile: deleteFile);
    await refresh();
  }
}
