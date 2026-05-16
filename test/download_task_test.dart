import 'package:flutter_test/flutter_test.dart';
import 'package:personal_media_archiver/core/models/download_task.dart';

DownloadTask make({
  int totalBytes = 0,
  int receivedBytes = 0,
  DownloadStatus status = DownloadStatus.queued,
  String? errorMessage,
}) {
  return DownloadTask(
    id: 'id-1',
    url: 'https://example.com/x.mp4',
    filename: 'x.mp4',
    savePath: '/tmp/x.mp4',
    totalBytes: totalBytes,
    receivedBytes: receivedBytes,
    status: status,
    errorMessage: errorMessage,
  );
}

void main() {
  group('DownloadTask.progress', () {
    test('totalBytes=0 → 0', () {
      expect(make().progress, 0);
    });

    test('totalBytes=100, received=50 → 0.5', () {
      expect(make(totalBytes: 100, receivedBytes: 50).progress, 0.5);
    });

    test('超過 1.0 會被 clamp 至 1.0', () {
      expect(make(totalBytes: 100, receivedBytes: 999).progress, 1.0);
    });

    test('received=0 → 0', () {
      expect(make(totalBytes: 100, receivedBytes: 0).progress, 0);
    });
  });

  group('DownloadTask.isActive', () {
    test('queued → true', () {
      expect(make(status: DownloadStatus.queued).isActive, isTrue);
    });
    test('running → true', () {
      expect(make(status: DownloadStatus.running).isActive, isTrue);
    });
    test('completed → false', () {
      expect(make(status: DownloadStatus.completed).isActive, isFalse);
    });
    test('failed → false', () {
      expect(make(status: DownloadStatus.failed).isActive, isFalse);
    });
    test('canceled → false', () {
      expect(make(status: DownloadStatus.canceled).isActive, isFalse);
    });
    test('paused → false', () {
      expect(make(status: DownloadStatus.paused).isActive, isFalse);
    });
  });

  group('DownloadTask.isTerminal', () {
    test('completed → true', () {
      expect(make(status: DownloadStatus.completed).isTerminal, isTrue);
    });
    test('failed → true', () {
      expect(make(status: DownloadStatus.failed).isTerminal, isTrue);
    });
    test('canceled → true', () {
      expect(make(status: DownloadStatus.canceled).isTerminal, isTrue);
    });
    test('queued → false', () {
      expect(make(status: DownloadStatus.queued).isTerminal, isFalse);
    });
    test('running → false', () {
      expect(make(status: DownloadStatus.running).isTerminal, isFalse);
    });
  });

  group('DownloadTask.needsCookies', () {
    test('errorMessage=null → false', () {
      expect(make(errorMessage: null).needsCookies, isFalse);
    });
    test('errorMessage 一般文字 → false', () {
      expect(make(errorMessage: 'some error').needsCookies, isFalse);
    });
    test('errorMessage 以 [NEEDS_COOKIES] prefix → true', () {
      expect(make(errorMessage: '[NEEDS_COOKIES] 需 cookies').needsCookies, isTrue);
    });
    test('errorMessage 中段含 [NEEDS_COOKIES] 但不在開頭 → false', () {
      expect(make(errorMessage: 'foo [NEEDS_COOKIES] bar').needsCookies, isFalse);
    });
  });

  group('DownloadTask.copyWith', () {
    test('未指定欄位保留原值', () {
      final t = make(totalBytes: 100, receivedBytes: 50);
      final c = t.copyWith();
      expect(c.totalBytes, 100);
      expect(c.receivedBytes, 50);
      expect(c.id, t.id);
      expect(c.url, t.url);
    });
    test('覆寫指定欄位', () {
      final t = make(status: DownloadStatus.queued);
      final c = t.copyWith(
        status: DownloadStatus.running,
        receivedBytes: 25,
        totalBytes: 100,
      );
      expect(c.status, DownloadStatus.running);
      expect(c.receivedBytes, 25);
      expect(c.totalBytes, 100);
    });
    test('copyWith 保留 cancelToken', () {
      final t = make();
      final c = t.copyWith(receivedBytes: 1);
      expect(identical(c.cancelToken, t.cancelToken), isTrue);
    });
  });
}
