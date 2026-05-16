import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/download/download_engine.dart';
import '../core/extractors/ytdlp_bridge.dart';
import '../core/models/download_task.dart';
import '../core/models/media_item.dart';
import 'providers.dart';

/// Immutable wrapper so Riverpod 比較時不會誤判同物件。
class DownloadTaskState {
  const DownloadTaskState({
    required this.task,
    required this.version,
    this.mode = TaskMode.directHttp,
  });

  final DownloadTask task;
  final int version;
  final TaskMode mode;
}

enum TaskMode { directHttp, ytdlp }

class TaskController extends StateNotifier<List<DownloadTaskState>> {
  TaskController(this._ref) : super(const []) {
    _ytSub = YtDlpBridge.instance.events().listen(_onYtEvent);
    // 預先啟動 yt-dlp 初始化（非阻塞），讓首次下載不卡頓
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      YtDlpBridge.instance.ensureInitialized().catchError((Object e) {
        // 初始化失敗時靜默；實際使用時會在下載時再次嘗試並回報
        return false;
      });
    });
  }

  final Ref _ref;
  StreamSubscription<YtDlpEvent>? _ytSub;
  int _runningCount = 0;
  int _versionCounter = 0;

  @override
  void dispose() {
    _ytSub?.cancel();
    super.dispose();
  }

  Future<DownloadTask> enqueue(String url) async {
    final policy = _ref.read(policyProvider);
    final rootDir = await _ref.read(downloadRootProvider.future);
    final useExtractor = policy.requiresExtractor(url);

    final filename = useExtractor
        ? '__pending__.mp4' // 由 yt-dlp 決定實際檔名
        : DownloadEngine.filenameFromUrl(url);
    final finalName =
        useExtractor ? filename : DownloadEngine.resolveCollision(rootDir.path, filename);
    final savePath = p.join(rootDir.path, finalName);

    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      filename: finalName,
      savePath: savePath,
    );

    _versionCounter += 1;
    state = [
      DownloadTaskState(
        task: task,
        version: _versionCounter,
        mode: useExtractor ? TaskMode.ytdlp : TaskMode.directHttp,
      ),
      ...state,
    ];

    _maybeStartNext();
    return task;
  }

  void _maybeStartNext() {
    final maxConcurrent = _ref.read(settingsProvider).maxConcurrent;
    while (_runningCount < maxConcurrent) {
      DownloadTaskState? next;
      for (final s in state) {
        if (s.task.status == DownloadStatus.queued) {
          next = s;
          break;
        }
      }
      if (next == null) return;
      _runningCount += 1;
      if (next.mode == TaskMode.ytdlp) {
        unawaited(_runYtDlp(next));
      } else {
        unawaited(_runDirect(next));
      }
    }
  }

  Future<void> _runDirect(DownloadTaskState st) async {
    final engine = _ref.read(downloadEngineProvider);
    await engine.download(
      st.task,
      onProgress: (t) {
        _replace(t);
      },
    );
    _runningCount = (_runningCount - 1).clamp(0, 999);
    await _afterTerminal(st.task);
    _maybeStartNext();
  }

  Future<void> _runYtDlp(DownloadTaskState st) async {
    final task = st.task;
    task.status = DownloadStatus.running;
    task.startedAt = DateTime.now();
    _replace(task);

    final rootDir = await _ref.read(downloadRootProvider.future);
    // 隱私保護：只把 cookies 傳給 YouTube extractor，避免 YouTube auth cookies
    // 洩漏給 Vimeo/Twitter/Threads 等其他 yt-dlp extractor
    final cookiesPath = _isYouTubeUrl(task.url)
        ? await _ref.read(cookiesServiceProvider).path()
        : null;
    try {
      await YtDlpBridge.instance.ensureInitialized();
      // 嘗試先取得 info 拿到 title
      try {
        final info = await YtDlpBridge.instance.getInfo(
          task.url,
          cookiesPath: cookiesPath,
        );
        if (info.title != null && info.title!.isNotEmpty) {
          task.filename = '${_sanitize(info.title!)}.${info.ext ?? 'mp4'}';
          _replace(task);
        }
      } catch (_) {
        // 不擋下載
      }

      final filepath = await YtDlpBridge.instance.download(
        taskId: task.id,
        url: task.url,
        outputDir: rootDir.path,
        cookiesPath: cookiesPath,
      );
      if (filepath != null && filepath.isNotEmpty) {
        task.savePath = filepath;
        task.filename = p.basename(filepath);
      }
      // 若 events 已經把 completed/failed 設好，就不重複
      if (!task.isTerminal) {
        try {
          final f = File(task.savePath);
          if (f.existsSync()) {
            final size = f.lengthSync();
            task.totalBytes = size;
            task.receivedBytes = size;
          }
        } catch (_) {}
        task.status = DownloadStatus.completed;
        task.finishedAt = DateTime.now();
      }
      _replace(task);
    } catch (e) {
      if (!task.isTerminal) {
        task.status = DownloadStatus.failed;
        task.errorMessage = _humanize(e);
        task.finishedAt = DateTime.now();
        _replace(task);
      }
    } finally {
      _runningCount = (_runningCount - 1).clamp(0, 999);
      await _afterTerminal(task);
      _maybeStartNext();
    }
  }

  void _onYtEvent(YtDlpEvent e) {
    final idx = state.indexWhere((s) => s.task.id == e.taskId);
    if (idx < 0) return;
    final task = state[idx].task;
    switch (e.type) {
      case YtDlpEventType.progress:
        // yt-dlp 進度是 0-100 百分比
        final pct = e.progress.clamp(0, 100);
        task.totalBytes = 100;
        task.receivedBytes = pct.toInt();
        _replace(task);
        break;
      case YtDlpEventType.completed:
        if (e.filepath.isNotEmpty) {
          task.savePath = e.filepath;
          task.filename = p.basename(e.filepath);
        }
        // 從實際磁碟讀取真實大小，覆寫 yt-dlp 用的百分比 placeholder
        try {
          final f = File(task.savePath);
          if (f.existsSync()) {
            final size = f.lengthSync();
            task.totalBytes = size;
            task.receivedBytes = size;
          } else {
            task.receivedBytes = task.totalBytes;
          }
        } catch (_) {
          task.receivedBytes = task.totalBytes;
        }
        task.status = DownloadStatus.completed;
        task.finishedAt = DateTime.now();
        _replace(task);
        break;
      case YtDlpEventType.failed:
        task.status = DownloadStatus.failed;
        // humanize：YouTube bot challenge 等錯誤套 [NEEDS_COOKIES] prefix
        // 讓 UI 能顯示「匯入 cookies」按鈕
        task.errorMessage = humanizeYtDlpError(Exception(e.error));
        task.finishedAt = DateTime.now();
        _replace(task);
        break;
      case YtDlpEventType.canceled:
        task.status = DownloadStatus.canceled;
        task.finishedAt = DateTime.now();
        _replace(task);
        break;
      case YtDlpEventType.unknown:
        break;
    }
  }

  Future<void> _afterTerminal(DownloadTask task) async {
    if (task.status != DownloadStatus.completed) return;
    if (!await File(task.savePath).exists()) return;
    try {
      final lib = await _ref.read(mediaLibraryProvider.future);
      final stat = await File(task.savePath).stat();
      await lib.add(
        MediaItem(
          id: task.id,
          title: p.basenameWithoutExtension(task.filename),
          filename: task.filename,
          filepath: task.savePath,
          sourceUrl: task.url,
          sizeBytes: stat.size,
          savedAt: task.finishedAt ?? DateTime.now(),
          mimeType: task.mimeType,
        ),
      );
      _ref.read(libraryControllerProvider.notifier).refresh();
    } catch (_) {}
  }

  void _replace(DownloadTask updated) {
    _versionCounter += 1;
    state = [
      for (final s in state)
        if (s.task.id == updated.id)
          DownloadTaskState(task: updated, version: _versionCounter, mode: s.mode)
        else
          s,
    ];
  }

  void cancel(String id) {
    final idx = state.indexWhere((s) => s.task.id == id);
    if (idx < 0) return;
    final s = state[idx];
    if (s.task.isTerminal) return;
    if (s.mode == TaskMode.ytdlp) {
      unawaited(YtDlpBridge.instance.cancel(id));
    } else {
      s.task.cancelToken.cancel('user');
    }
  }

  void remove(String id) {
    state = [for (final s in state) if (s.task.id != id) s];
  }

  void clearTerminal() {
    state = [for (final s in state) if (!s.task.isTerminal) s];
  }

  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// YouTube host check — 嚴格 match 避免把 cookies 傳給其他 yt-dlp extractor。
  /// 涵蓋：youtube.com、m.youtube.com、music.youtube.com、youtu.be、youtube-nocookie.com
  bool _isYouTubeUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return host == 'youtube.com' ||
          host.endsWith('.youtube.com') ||
          host == 'youtu.be' ||
          host.endsWith('.youtu.be') ||
          host == 'youtube-nocookie.com' ||
          host.endsWith('.youtube-nocookie.com');
    } catch (_) {
      return false;
    }
  }

  String _humanize(Object e) => humanizeYtDlpError(e);
}

/// 將 yt-dlp / native exception 轉成 user-friendly 訊息
/// （從 [TaskController._humanize] 抽出來方便 unit test）
String humanizeYtDlpError(Object e) {
  final s = e.toString();
  final lc = s.toLowerCase();
  // YouTube 反爬：需要 user 匯入 cookies。errorMessage 加 prefix 讓 UI 顯示
  // 「匯入 cookies」按鈕（DownloadTask.needsCookies 從此 prefix 推斷）
  if (s.contains('Sign in to confirm') ||
      lc.contains('cookies-from-browser') ||
      lc.contains('not a bot')) {
    return '[NEEDS_COOKIES] 此來源需要 cookies；請至設定 → 進階 → 匯入 YouTube cookies';
  }
  if (s.contains('Private video')) {
    return '此影片為私人內容。';
  }
  if (s.contains('DRM')) {
    return '此內容受 DRM 保護，不支援。';
  }
  return s.length > 200 ? s.substring(0, 200) : s;
}
