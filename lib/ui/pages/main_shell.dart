import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/cookies/cookies_service.dart';
import '../../state/providers.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'queue_page.dart';
import 'settings_page.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _pages = <Widget>[
    HomePage(),
    QueuePage(),
    LibraryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskControllerProvider);
    final activeCount = tasks.where((t) => t.task.isActive).length;
    final index = ref.watch(selectedTabProvider);

    // 訂閱 cookies share intent — Firefox 等 app share 過來會自動 import + SnackBar
    ref.listen<AsyncValue<String>>(cookiesShareStreamProvider, (prev, next) {
      next.whenData((content) async {
        final service = ref.read(cookiesServiceProvider);
        final messenger = ScaffoldMessenger.maybeOf(context);
        try {
          final meta = await service.importFromContent(content);
          ref.invalidate(cookiesExistsProvider);
          messenger?.showSnackBar(
            SnackBar(
              content: Text('已自動匯入 cookies（${meta.domainCount} domain）'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
        } on CookiesValidationException catch (e) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text('cookies 匯入失敗：${e.message}'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        } catch (e) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text('cookies 匯入失敗：$e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      });
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).state = i,
        destinations: [
          const NavigationDestination(
            icon: Icon(Symbols.add_link_rounded),
            selectedIcon: Icon(Symbols.add_link_rounded, fill: 1),
            label: '新增',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Symbols.download_rounded),
            ),
            selectedIcon: const Icon(Symbols.download_rounded, fill: 1),
            label: '佇列',
          ),
          const NavigationDestination(
            icon: Icon(Symbols.video_library_rounded),
            selectedIcon: Icon(Symbols.video_library_rounded, fill: 1),
            label: '媒體庫',
          ),
          const NavigationDestination(
            icon: Icon(Symbols.settings_rounded),
            selectedIcon: Icon(Symbols.settings_rounded, fill: 1),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
