import 'package:flutter_test/flutter_test.dart';

import 'package:personal_media_archiver/core/download/download_engine.dart';

void main() {
  test('filenameFromUrl 從常見 URL 取出 basename', () {
    expect(
      DownloadEngine.filenameFromUrl(
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      ),
      'BigBuckBunny.mp4',
    );
    expect(
      DownloadEngine.filenameFromUrl('https://example.com/path/to/file.mp3'),
      'file.mp3',
    );
  });

  test('filenameFromUrl 處理 URL 解碼', () {
    expect(
      DownloadEngine.filenameFromUrl('https://example.com/foo%20bar.mp4'),
      'foo bar.mp4',
    );
  });

  test('filenameFromUrl 在無 path 時 fallback', () {
    expect(
      DownloadEngine.filenameFromUrl('https://example.com'),
      'media',
    );
    expect(
      DownloadEngine.filenameFromUrl('https://example.com/'),
      'media',
    );
  });

  test('filenameFromUrl 過濾非法字元', () {
    // URL-encode 非法字元，decode 後應該被 sanitize regex 替換
    expect(
      DownloadEngine.filenameFromUrl('https://example.com/a%3Ab%2Ac.mp4'),
      'a_b_c.mp4',
    );
  });
}
