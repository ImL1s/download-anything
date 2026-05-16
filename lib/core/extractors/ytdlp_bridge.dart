import 'dart:async';

import 'package:flutter/services.dart';

/// Flutter side wrapper for the native youtubedl-android bridge.
///
/// 對應 Android MainActivity.kt 提供的 MethodChannel `dev.pma/ytdl` 與
/// EventChannel `dev.pma/ytdl_events`。所有方法都是 async，回傳值是 native
/// 端送回的 plain map / value。
class YtDlpBridge {
  YtDlpBridge._();

  static final YtDlpBridge instance = YtDlpBridge._();

  static const _method = MethodChannel('dev.pma/ytdl');
  static const _events = EventChannel('dev.pma/ytdl_events');

  Stream<YtDlpEvent>? _eventStream;
  bool _initStarted = false;
  Future<bool>? _initFuture;

  /// 確保 native 端的 YoutubeDL 已初始化。
  ///
  /// init 過程包含解壓 Python runtime；首次冷啟動可能需要 2-5 秒。
  Future<bool> ensureInitialized() {
    if (_initFuture != null) return _initFuture!;
    _initStarted = true;
    _initFuture = _method.invokeMethod<bool>('init').then((v) => v ?? false);
    return _initFuture!;
  }

  /// 取得 yt-dlp 版本字串，方便診斷與顯示在設定頁。
  Future<String> version() async {
    final v = await _method.invokeMethod<String>('version');
    return v ?? 'unknown';
  }

  /// 手動觸發 yt-dlp 更新（STABLE 通道）。
  /// 回傳 (status, versionName)。
  Future<({String status, String version})> update() async {
    final res = await _method.invokeMethod<dynamic>('update');
    if (res is Map) {
      return (
        status: res['status']?.toString() ?? 'unknown',
        version: res['version']?.toString() ?? 'unknown',
      );
    }
    return (status: 'unknown', version: 'unknown');
  }

  /// 取得 URL 的中繼資料；底層走 `yt-dlp --dump-json`。
  /// [cookiesPath]：非 null 時 native 端會加 `--cookies <path>` 給 yt-dlp。
  Future<YtDlpVideoInfo> getInfo(String url, {String? cookiesPath}) async {
    final res = await _method.invokeMethod<dynamic>('getInfo', {
      'url': url,
      'cookiesPath': cookiesPath,
    });
    if (res is Map) {
      return YtDlpVideoInfo.fromMap(Map<String, dynamic>.from(res));
    }
    throw const FormatException('Unexpected getInfo response shape');
  }

  /// 下載指定 URL 到 [outputDir]，回傳最終檔案絕對路徑。
  /// [cookiesPath]：非 null 時 native 端會加 `--cookies <path>` 給 yt-dlp，
  /// 用於 YouTube 等反爬站點。
  Future<String?> download({
    required String taskId,
    required String url,
    required String outputDir,
    bool audioOnly = false,
    String? cookiesPath,
  }) async {
    final res = await _method.invokeMethod<String>('download', {
      'taskId': taskId,
      'url': url,
      'outputDir': outputDir,
      'audioOnly': audioOnly,
      'cookiesPath': cookiesPath,
    });
    return res;
  }

  /// 取消對應 taskId 的下載；底層呼叫 destroyProcessById。
  Future<bool> cancel(String taskId) async {
    final r = await _method.invokeMethod<bool>('cancel', {'taskId': taskId});
    return r ?? false;
  }

  /// 訂閱 native 端事件，回傳已強型別化的 stream。
  Stream<YtDlpEvent> events() {
    _eventStream ??= _events.receiveBroadcastStream().map((raw) {
      if (raw is Map) {
        return YtDlpEvent.fromMap(Map<String, dynamic>.from(raw));
      }
      return YtDlpEvent(
        taskId: '',
        type: YtDlpEventType.unknown,
        raw: const {},
      );
    });
    return _eventStream!;
  }

  bool get hasStartedInit => _initStarted;
}

class YtDlpVideoInfo {
  YtDlpVideoInfo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnail,
    required this.extractor,
    required this.webpageUrl,
    required this.description,
    required this.ext,
  });

  final String? id;
  final String? title;
  final String? uploader;
  final num? duration;
  final String? thumbnail;
  final String? extractor;
  final String? webpageUrl;
  final String? description;
  final String? ext;

  factory YtDlpVideoInfo.fromMap(Map<String, dynamic> m) {
    return YtDlpVideoInfo(
      id: m['id']?.toString(),
      title: m['title']?.toString(),
      uploader: m['uploader']?.toString(),
      duration: m['duration'] is num ? m['duration'] as num : null,
      thumbnail: m['thumbnail']?.toString(),
      extractor: m['extractor']?.toString(),
      webpageUrl: m['webpageUrl']?.toString(),
      description: m['description']?.toString(),
      ext: m['ext']?.toString(),
    );
  }
}

enum YtDlpEventType { progress, completed, failed, canceled, unknown }

class YtDlpEvent {
  const YtDlpEvent({
    required this.taskId,
    required this.type,
    required this.raw,
  });

  final String taskId;
  final YtDlpEventType type;
  final Map<String, dynamic> raw;

  double get progress => (raw['progress'] as num?)?.toDouble() ?? 0;
  num get etaSec => (raw['etaSec'] as num?) ?? 0;
  String get line => raw['line']?.toString() ?? '';
  String get filepath => raw['filepath']?.toString() ?? '';
  String get error => raw['error']?.toString() ?? '';

  factory YtDlpEvent.fromMap(Map<String, dynamic> m) {
    final t = switch (m['type']?.toString()) {
      'progress' => YtDlpEventType.progress,
      'completed' => YtDlpEventType.completed,
      'failed' => YtDlpEventType.failed,
      'canceled' => YtDlpEventType.canceled,
      _ => YtDlpEventType.unknown,
    };
    return YtDlpEvent(
      taskId: m['taskId']?.toString() ?? '',
      type: t,
      raw: m,
    );
  }
}
