import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/cookies/cookies_service.dart';
import '../core/download/download_engine.dart';
import '../core/library/media_library.dart';
import '../core/policy/source_policy.dart';
import 'task_controller.dart';
import 'library_controller.dart';
import 'settings_controller.dart';

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController();
});

final policyProvider = Provider<SourcePolicy>((ref) {
  final s = ref.watch(settingsProvider);
  return SourcePolicy(strictness: s.strictness);
});

final downloadEngineProvider = Provider<DownloadEngine>((ref) {
  return DownloadEngine();
});

final downloadRootProvider = FutureProvider<Directory>((ref) async {
  // 使用 app 私有外部存放區，避免 All Files Access 權限
  final base = await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, 'PersonalMediaArchiver'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
});

final mediaLibraryProvider = FutureProvider<MediaLibrary>((ref) async {
  return MediaLibrary.open();
});

final taskControllerProvider =
    StateNotifierProvider<TaskController, List<DownloadTaskState>>((ref) {
  return TaskController(ref);
});

final libraryControllerProvider =
    StateNotifierProvider<LibraryController, LibraryState>((ref) {
  return LibraryController(ref);
});

final cookiesServiceProvider = Provider<CookiesService>((ref) => CookiesService());

/// 是否已匯入 YouTube cookies；UI 用來顯示 hint / 隱藏匯入提示
final cookiesExistsProvider = FutureProvider<bool>((ref) async {
  return ref.read(cookiesServiceProvider).exists();
});

/// 主 Shell 當前 tab index；其他頁面可呼叫
/// `ref.read(selectedTabProvider.notifier).state = 3;` 切到設定 tab
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// 監聽 native EventChannel `dev.pma/cookies_share` 推來的 cookies content
/// （Firefox / 其他 app 透過 Android share intent 送到 PMA）
/// Stream emits raw Netscape cookies text；UI 端可訂閱自動呼叫 importFromContent
final cookiesShareStreamProvider = StreamProvider<String>((ref) {
  const channel = EventChannel('dev.pma/cookies_share');
  return channel.receiveBroadcastStream().map((event) => event as String);
});

/// 監聽 native EventChannel `dev.pma/share_url` 推來的 URL 字串
/// （YouTube/Twitter/Chrome 等 app 透過 Android share intent 分享 link 到 PMA）
/// Stream emits raw URL string；UI 端訂閱後自動 enqueue 下載任務
final shareUrlStreamProvider = StreamProvider<String>((ref) {
  const channel = EventChannel('dev.pma/share_url');
  return channel.receiveBroadcastStream().map((event) => event as String);
});

/// 自動匯入結果 — main_shell 觀察 cookiesShareStreamProvider 並用 CookiesService 處理
class CookiesAutoImportResult {
  const CookiesAutoImportResult.success(this.meta) : error = null;
  const CookiesAutoImportResult.failure(this.error) : meta = null;
  final CookiesMeta? meta;
  final String? error;
  bool get ok => meta != null;
}
