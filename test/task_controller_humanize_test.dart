import 'package:flutter_test/flutter_test.dart';
import 'package:personal_media_archiver/state/task_controller.dart';

void main() {
  group('humanizeYtDlpError', () {
    test('Sign in to confirm → [NEEDS_COOKIES] prefix', () {
      final s = humanizeYtDlpError(
        Exception('ERROR: [youtube] xxx: Sign in to confirm you are not a bot.'),
      );
      expect(s, startsWith('[NEEDS_COOKIES] '));
      expect(s, contains('進階'));
      expect(s, contains('YouTube cookies'));
    });

    test('cookies-from-browser → [NEEDS_COOKIES]', () {
      final s = humanizeYtDlpError(
        Exception('Use --cookies-from-browser or --cookies for the authentication'),
      );
      expect(s, startsWith('[NEEDS_COOKIES] '));
    });

    test('not a bot (lowercase) → [NEEDS_COOKIES]', () {
      final s = humanizeYtDlpError(Exception('Confirm you are not a bot'));
      expect(s, startsWith('[NEEDS_COOKIES] '));
    });

    test('Private video → 私人內容訊息', () {
      final s = humanizeYtDlpError(Exception('Private video: Sign in if you have access'));
      // 注意：先 hit 'Sign in to confirm' check 才會 fallthrough；但這裡訊息含 Sign in 不含 'to confirm'
      // 實作邏輯：先檢 Sign in to confirm / cookies-from-browser / not a bot；再檢 Private video
      // 此 case 不 match 第一組所以 hit Private video
      expect(s, contains('私人內容'));
    });

    test('DRM → DRM 保護訊息', () {
      final s = humanizeYtDlpError(Exception('Content protected by DRM'));
      expect(s, contains('DRM'));
      expect(s, contains('保護'));
    });

    test('超長訊息截斷至 200 字元', () {
      final long = 'X' * 500;
      final s = humanizeYtDlpError(Exception(long));
      expect(s.length, lessThanOrEqualTo(200));
    });

    test('一般短訊息原樣回傳', () {
      final s = humanizeYtDlpError(Exception('Some short error'));
      expect(s, contains('Some short error'));
    });

    test('不會把含 SIGN IN 的非 bot 訊息誤判為 needsCookies', () {
      // 大小寫敏感檢 'Sign in to confirm'；'sign in' 不應 match
      final s = humanizeYtDlpError(Exception('please sign in to your account'));
      expect(s, isNot(startsWith('[NEEDS_COOKIES] ')));
    });
  });
}
