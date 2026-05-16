import 'package:dio/dio.dart';

enum DownloadStatus {
  queued,
  running,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.filename,
    required this.savePath,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    this.startedAt,
    this.finishedAt,
    this.mimeType,
    CancelToken? cancelToken,
  }) : cancelToken = cancelToken ?? CancelToken();

  final String id;
  final String url;
  String filename;
  String savePath;
  int totalBytes;
  int receivedBytes;
  DownloadStatus status;
  String? errorMessage;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? mimeType;
  CancelToken cancelToken;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0, 1);
  }

  bool get isActive =>
      status == DownloadStatus.running || status == DownloadStatus.queued;

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled;

  /// True 表示此 task 失敗原因是 YouTube 反爬 — UI 可顯示「匯入 cookies」按鈕
  bool get needsCookies => (errorMessage ?? '').startsWith('[NEEDS_COOKIES]');

  DownloadTask copyWith({
    int? totalBytes,
    int? receivedBytes,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? mimeType,
    String? filename,
    String? savePath,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      filename: filename ?? this.filename,
      savePath: savePath ?? this.savePath,
      totalBytes: totalBytes ?? this.totalBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      mimeType: mimeType ?? this.mimeType,
      cancelToken: cancelToken,
    );
  }
}
