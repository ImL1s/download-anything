import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

/// 媒體庫：以 JSON 檔案保存 [MediaItem] 索引。
///
/// 不使用 sqflite 等 native plugin，降低 plugin 相容性風險；資料量大時可後續
/// 升級為 sqlite。
class MediaLibrary {
  MediaLibrary._(this._indexFile, this._items);

  final File _indexFile;
  final List<MediaItem> _items;

  static Future<MediaLibrary> open() async {
    final dir = await getApplicationSupportDirectory();
    final indexFile = File(p.join(dir.path, 'library.json'));
    if (!await indexFile.exists()) {
      await indexFile.create(recursive: true);
      await indexFile.writeAsString(jsonEncode({'items': []}));
    }
    final raw = await indexFile.readAsString();
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      parsed = {'items': []};
    }
    final list = (parsed['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MediaItem.fromJson)
        .toList();
    return MediaLibrary._(indexFile, list);
  }

  List<MediaItem> get items => List.unmodifiable(_items);

  Future<void> add(MediaItem item) async {
    _items.add(item);
    await _flush();
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final idx = _items.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    final removed = _items.removeAt(idx);
    if (deleteFile) {
      final f = File(removed.filepath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await _flush();
  }

  Future<void> clear({bool deleteFiles = false}) async {
    if (deleteFiles) {
      for (final m in _items) {
        final f = File(m.filepath);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
    _items.clear();
    await _flush();
  }

  Future<void> _flush() async {
    final json = {'items': _items.map((m) => m.toJson()).toList()};
    await _indexFile.writeAsString(jsonEncode(json));
  }
}
