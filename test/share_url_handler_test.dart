import 'package:flutter_test/flutter_test.dart';
import 'package:personal_media_archiver/core/models/policy_decision.dart';
import 'package:personal_media_archiver/core/policy/source_policy.dart';
import 'package:personal_media_archiver/state/share_url_handler.dart';

void main() {
  group('isLikelyShareUrl', () {
    test('valid http(s) URL → true', () {
      expect(isLikelyShareUrl('https://vimeo.com/76979871'), isTrue);
      expect(isLikelyShareUrl('http://example.com/path'), isTrue);
      expect(isLikelyShareUrl('https://youtu.be/jNQXAC9IVRw'), isTrue);
    });

    test('no http(s) scheme → false', () {
      expect(isLikelyShareUrl('vimeo.com/76979871'), isFalse);
      expect(isLikelyShareUrl('ftp://example.com'), isFalse);
      expect(isLikelyShareUrl('just plain text'), isFalse);
    });

    test('multiline / whitespace content → false', () {
      expect(isLikelyShareUrl('https://vimeo.com/76979871\nextra'), isFalse);
      expect(isLikelyShareUrl('Check this: https://vimeo.com/76979871'), isFalse);
      expect(isLikelyShareUrl('https://vimeo.com/76979871\textra'), isFalse);
    });

    test('overlength (>2048) → false', () {
      final huge = 'https://example.com/${'a' * 2050}';
      expect(isLikelyShareUrl(huge), isFalse);
    });

    test('missing host → false', () {
      expect(isLikelyShareUrl('https://'), isFalse);
    });

    test('empty / very short → false', () {
      expect(isLikelyShareUrl(''), isFalse);
      expect(isLikelyShareUrl('https://a'), isTrue); // valid even if a is the host
    });
  });

  group('classifyShare', () {
    const policy = SourcePolicy();

    test('YouTube → ALLOW → ShareUrlAutoEnqueue', () {
      final action = classifyShare('https://youtu.be/jNQXAC9IVRw', policy);
      expect(action, isA<ShareUrlAutoEnqueue>());
      expect((action as ShareUrlAutoEnqueue).url, 'https://youtu.be/jNQXAC9IVRw');
      expect(action.decision.verdict, PolicyVerdict.allow);
    });

    test('Vimeo → ALLOW → ShareUrlAutoEnqueue', () {
      final action = classifyShare('https://vimeo.com/76979871', policy);
      expect(action, isA<ShareUrlAutoEnqueue>());
    });

    test('Netflix (DRM) → BLOCK → ShareUrlBlocked', () {
      final action = classifyShare('https://www.netflix.com/title/123', policy);
      expect(action, isA<ShareUrlBlocked>());
      expect(action.decision.verdict, PolicyVerdict.block);
    });

    test('Hami Video (台灣 OTT) → BLOCK → ShareUrlBlocked', () {
      final action = classifyShare('https://hamivideo.hinet.net/x', policy);
      expect(action, isA<ShareUrlBlocked>());
    });

    test('unknown host (balanced) → WARN → ShareUrlNeedsConsent', () {
      final action = classifyShare('https://random-unknown.example.com/p/1', policy);
      expect(action, isA<ShareUrlNeedsConsent>());
      expect((action as ShareUrlNeedsConsent).url,
          'https://random-unknown.example.com/p/1');
      expect(action.decision.verdict, PolicyVerdict.warn);
    });

    test('unknown host in strict mode → BLOCK', () {
      const strictPolicy = SourcePolicy(strictness: PolicyStrictness.strict);
      final action =
          classifyShare('https://random-unknown.example.com/p/1', strictPolicy);
      expect(action, isA<ShareUrlBlocked>());
    });

    test('direct mp4 → ALLOW (direct, not extractor)', () {
      final action = classifyShare(
        'https://commondatastorage.googleapis.com/sample.mp4',
        policy,
      );
      expect(action, isA<ShareUrlAutoEnqueue>());
    });
  });
}
