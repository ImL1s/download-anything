import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/media_item.dart';
import '../../state/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/media_card.dart';

enum LibrarySort {
  dateDesc('下載時間（新→舊）'),
  dateAsc('下載時間（舊→新）'),
  nameAsc('檔名'),
  sizeDesc('大小（大→小）');

  const LibrarySort(this.label);
  final String label;
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String _query = '';
  LibrarySort _sort = LibrarySort.dateDesc;
  bool _searchOpen = false;
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<MediaItem> _filterAndSort(List<MediaItem> items) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? List<MediaItem>.from(items)
        : items.where((it) {
            final t = it.title.toLowerCase();
            final f = it.filename.toLowerCase();
            return t.contains(q) || f.contains(q);
          }).toList();
    switch (_sort) {
      case LibrarySort.dateDesc:
        filtered.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      case LibrarySort.dateAsc:
        filtered.sort((a, b) => a.savedAt.compareTo(b.savedAt));
      case LibrarySort.nameAsc:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case LibrarySort.sizeDesc:
        filtered.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryControllerProvider);
    final shown = _filterAndSort(lib.items);

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜尋媒體（檔名或標題）',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('媒體庫'),
        actions: [
          IconButton(
            tooltip: _searchOpen ? '關閉搜尋' : '搜尋',
            icon: Icon(_searchOpen ? Symbols.close_rounded : Symbols.search_rounded),
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchCtl.clear();
                  _query = '';
                }
              });
            },
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: '排序',
            icon: const Icon(Symbols.sort_rounded),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => LibrarySort.values
                .map((s) => PopupMenuItem<LibrarySort>(
                      value: s,
                      child: Row(
                        children: [
                          if (s == _sort)
                            const Icon(Symbols.check_rounded, size: 18)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(s.label),
                        ],
                      ),
                    ))
                .toList(),
          ),
          IconButton(
            tooltip: '重新整理',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: () =>
                ref.read(libraryControllerProvider.notifier).refresh(),
          ),
        ],
      ),
      body: lib.loading
          ? const Center(child: CircularProgressIndicator())
          : lib.items.isEmpty
              ? const EmptyState(
                  icon: Symbols.video_library_rounded,
                  title: '媒體庫是空的',
                  subtitle: '下載完成的媒體會出現在這裡',
                )
              : shown.isEmpty
                  ? EmptyState(
                      icon: Symbols.search_off_rounded,
                      title: '沒有符合「$_query」的結果',
                      subtitle: '試試其他關鍵字或清除搜尋',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return MediaCard(
                          key: ValueKey(item.id),
                          item: item,
                          onTap: () async {
                            final uri = Uri.file(item.filepath);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('找不到可開啟此檔案的應用程式')),
                              );
                            }
                          },
                          onDelete: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('刪除媒體'),
                                content: const Text('要同時刪除檔案嗎？'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('僅從索引移除'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('刪除檔案'),
                                  ),
                                ],
                              ),
                            );
                            if (!context.mounted || confirm == null) return;
                            await ref
                                .read(libraryControllerProvider.notifier)
                                .remove(item.id, deleteFile: confirm);
                          },
                        );
                      },
                    ),
    );
  }
}
