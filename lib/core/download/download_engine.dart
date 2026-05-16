import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../models/download_task.dart';

/// 純 HTTP 下載引擎。
///
/// 不依賴任何第三方擷取器；只負責對已決定的 URL 做 GET，把回應寫入指定路徑。
/// 提供進度 callback 與 cancel token；允許簡單的 Range 續傳。
class DownloadEngine {
  DownloadEngine({Dio? dio}) : _dio = dio ?? _buildDefaultDio();

  final Dio _dio;

  static Dio _buildDefaultDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
        maxRedirects: 8,
        responseType: ResponseType.stream,
        headers: {
          'User-Agent': 'PersonalMediaArchiver/0.1 (+local; no telemetry)',
          'Accept': '*/*',
        },
      ),
    );
    return dio;
  }

  /// 對 [url] 做 HEAD 試探，取得檔案大小與 Content-Type。
  /// 若 HEAD 失敗（部分 CDN 不允許），回傳空資料但不丟例外。
  Future<HeadProbe> probe(String url) async {
    try {
      final resp = await _dio.head<dynamic>(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final headers = resp.headers;
      final lenStr = headers.value(Headers.contentLengthHeader);
      final ct = headers.value(Headers.contentTypeHeader);
      return HeadProbe(
        contentLength: lenStr != null ? int.tryParse(lenStr) : null,
        contentType: ct,
        finalUrl: resp.realUri.toString(),
        acceptsRanges:
            (headers.value('accept-ranges') ?? '').toLowerCase().contains('bytes'),
      );
    } catch (_) {
      return const HeadProbe(
        contentLength: null,
        contentType: null,
        finalUrl: null,
        acceptsRanges: false,
      );
    }
  }

  /// 依照 [task] 進行下載，邊寫檔邊回報進度。
  ///
  /// 回傳更新後的 [DownloadTask]（包含最終 status / size / mimeType）。
  Future<DownloadTask> download(
    DownloadTask task, {
    required void Function(DownloadTask) onProgress,
  }) async {
    final file = File(task.savePath);
    await file.parent.create(recursive: true);

    final probe = await this.probe(task.url);
    if (probe.contentLength != null) {
      task.totalBytes = probe.contentLength!;
    }
    if (probe.contentType != null) {
      task.mimeType = _normalizeContentType(probe.contentType!);
    }

    task.status = DownloadStatus.running;
    task.startedAt ??= DateTime.now();
    onProgress(task);

    try {
      final response = await _dio.get<ResponseBody>(
        task.url,
        cancelToken: task.cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': '*/*'},
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const FormatException('Empty response body');
      }

      // 補抓 Content-Length（GET 通常比 HEAD 可靠）
      final clHeader = response.headers.value(Headers.contentLengthHeader);
      if (clHeader != null) {
        final cl = int.tryParse(clHeader);
        if (cl != null && cl > 0) task.totalBytes = cl;
      }
      final ct = response.headers.value(Headers.contentTypeHeader);
      if (ct != null) {
        task.mimeType = _normalizeContentType(ct);
      }

      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in body.stream) {
          if (task.cancelToken.isCancelled) {
            break;
          }
          sink.add(chunk);
          received += chunk.length;
          task.receivedBytes = received;
          onProgress(task);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (task.cancelToken.isCancelled) {
        // 刪除半成品檔案
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        task.status = DownloadStatus.canceled;
        task.finishedAt = DateTime.now();
        onProgress(task);
        return task;
      }

      if (task.totalBytes <= 0) {
        // 沒有 Content-Length 的情況：以實際接收量為準
        task.totalBytes = received;
      }
      task.status = DownloadStatus.completed;
      task.finishedAt = DateTime.now();
      onProgress(task);
      return task;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.canceled;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = _humanizeError(e);
      }
      task.finishedAt = DateTime.now();
      // 嘗試刪除半成品
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      onProgress(task);
      return task;
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      task.finishedAt = DateTime.now();
      onProgress(task);
      return task;
    }
  }

  String _humanizeError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '連線逾時，請檢查網路或來源伺服器。';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return '伺服器回應 $code（${e.response?.statusMessage ?? ''}）';
      case DioExceptionType.cancel:
        return '已取消';
      case DioExceptionType.badCertificate:
        return '伺服器憑證驗證失敗。';
      case DioExceptionType.connectionError:
        return '無法連線到伺服器。';
      case DioExceptionType.unknown:
        return e.message ?? e.toString();
    }
  }

  String _normalizeContentType(String raw) {
    try {
      final mt = MediaType.parse(raw);
      return '${mt.type}/${mt.subtype}';
    } catch (_) {
      return raw.split(';').first.trim();
    }
  }

  /// 由 URL 推導預設檔名。
  static String filenameFromUrl(String url, {String fallback = 'media'}) {
    try {
      final uri = Uri.parse(url);
      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (last.isEmpty) return fallback;
      final decoded = Uri.decodeComponent(last);
      // 移除非常見字元
      final cleaned = decoded.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      return cleaned.isEmpty ? fallback : cleaned;
    } catch (_) {
      return fallback;
    }
  }

  /// 處理重複檔名：若已存在，加上 (1)/(2)/…
  static String resolveCollision(String dir, String filename) {
    final ext = p.extension(filename);
    final stem = p.basenameWithoutExtension(filename);
    var attempt = 0;
    var candidate = filename;
    while (File(p.join(dir, candidate)).existsSync()) {
      attempt += 1;
      candidate = '$stem ($attempt)$ext';
      if (attempt > 9999) break;
    }
    return candidate;
  }
}

class HeadProbe {
  const HeadProbe({
    required this.contentLength,
    required this.contentType,
    required this.finalUrl,
    required this.acceptsRanges,
  });

  final int? contentLength;
  final String? contentType;
  final String? finalUrl;
  final bool acceptsRanges;
}
