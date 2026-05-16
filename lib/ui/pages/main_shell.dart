import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/cookies/cookies_service.dart';
import '../../core/models/policy_decision.dart';
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

    // 訂閱 share URL intent — 其他 app (YouTube/Twitter/Chrome) share 一個 link 過來
    // 安全策略：
    //   - verdict == ALLOW（明確政策放行）→ 自動 enqueue + SnackBar + 切佇列 tab
    //   - verdict == WARN（未知 host，平衡 mode）→ 不自動 enqueue，顯示 SnackBar 引導 user 手動到首頁確認
    //   - verdict == BLOCK → 顯示 SnackBar 告知被擋
    // 為什麼不在 WARN 自動 enqueue：MainActivity 是 exported，任何 app 都能送 ACTION_SEND；
    // SnackBar 在 enqueue 後出現等於事後通知，不是 user consent — 必須在 verdict 不夠強時要求 user 互動。
    ref.listen<AsyncValue<String>>(shareUrlStreamProvider, (prev, next) {
      next.whenData((url) async {
        final policy = ref.read(policyProvider);
        final decision = policy.classify(url);
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (decision.verdict == PolicyVerdict.block) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text('分享的網址被政策擋下：${decision.reason}'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
        if (decision.verdict == PolicyVerdict.warn) {
          // WARN：要求 user consent — prefill URL 到首頁 textfield + 切首頁 tab，
          // user 看到完整 URL + policy banner 決定要不要 download (NOT auto-enqueue)
          ref.read(pendingShareUrlForReviewProvider.notifier).state = url;
          ref.read(selectedTabProvider.notifier).state = 0;
          messenger?.showSnackBar(
            SnackBar(
              content: Text('分享網址未知來源（${decision.host}）— 已預填到首頁，請確認後按「開始下載」'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
        // verdict == ALLOW → 政策明確放行，可自動 enqueue
        try {
          final task = await ref.read(taskControllerProvider.notifier).enqueue(url);
          messenger?.showSnackBar(
            SnackBar(
              content: Text('已從分享建立下載：${task.filename}'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
            ),
          );
          ref.read(selectedTabProvider.notifier).state = 1;
        } catch (e) {
          messenger?.showSnackBar(
            SnackBar(
              content: Text('分享下載失敗：$e'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      });
    });

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
