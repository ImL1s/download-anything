import 'package:flutter_test/flutter_test.dart';

import 'package:personal_media_archiver/core/policy/source_policy.dart';
import 'package:personal_media_archiver/core/models/policy_decision.dart';

void main() {
  test('Policy: 直連 mp4 為 ALLOW', () {
    const p = SourcePolicy();
    final d = p.classify(
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    );
    expect(d.verdict, PolicyVerdict.allow);
  });

  test('Policy: Netflix 為 BLOCK', () {
    const p = SourcePolicy();
    final d = p.classify('https://www.netflix.com/title/12345');
    expect(d.verdict, PolicyVerdict.block);
  });

  test('Policy: YouTube 走 yt-dlp，為 ALLOW', () {
    const p = SourcePolicy();
    final d = p.classify('https://www.youtube.com/watch?v=abc');
    expect(d.verdict, PolicyVerdict.allow);
  });

  test('Policy: TikTok 為 ALLOW', () {
    const p = SourcePolicy();
    final d = p.classify('https://www.tiktok.com/@user/video/123');
    expect(d.verdict, PolicyVerdict.allow);
  });

  test('Policy: Threads 為 ALLOW（both .net and .com）', () {
    const p = SourcePolicy();
    final d1 = p.classify('https://www.threads.net/@user/post/abc');
    final d2 = p.classify('https://www.threads.com/@user/post/abc');
    expect(d1.verdict, PolicyVerdict.allow);
    expect(d2.verdict, PolicyVerdict.allow);
  });

  test('Policy: 空白為 BLOCK', () {
    const p = SourcePolicy();
    expect(p.classify('').verdict, PolicyVerdict.block);
    expect(p.classify('   ').verdict, PolicyVerdict.block);
  });

  test('Policy: requiresExtractor 區分直連與社交平台', () {
    const p = SourcePolicy();
    expect(p.requiresExtractor('https://example.com/a.mp4'), isFalse);
    expect(p.requiresExtractor('https://www.youtube.com/watch?v=abc'), isTrue);
  });

  test('Policy: 嚴格模式對未知 host 為 BLOCK', () {
    const p = SourcePolicy(strictness: PolicyStrictness.strict);
    final d = p.classify('https://random-unknown.example.com/page');
    expect(d.verdict, PolicyVerdict.block);
  });

  test('Policy: 台灣 OTT (Hami / Catchplay / Viu / Vidol / MOD) 為 BLOCK', () {
    const p = SourcePolicy();
    for (final url in [
      'https://hamivideo.hinet.net/watch/abc',
      'https://www.catchplay.com/zh-TW/program/xxx',
      'https://www.viu.com/ott/tw/zh-tw/all/123',
      'https://www.viu.tv/encore/abc',
      'https://www.vidol.tv/Drama/123',
      'https://www.pubu.com.tw/magazine/123',
      'https://www.bookwalker.com.tw/product/123',
      'https://tw.iqiyi.com.tw/v/abc.html',
      'https://mod.cht.com.tw/program/abc',
    ]) {
      expect(p.classify(url).verdict, PolicyVerdict.block,
          reason: 'expected BLOCK for $url');
    }
  });
}
