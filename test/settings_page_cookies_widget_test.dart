import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_media_archiver/core/cookies/cookies_service.dart';
import 'package:personal_media_archiver/state/providers.dart';
import 'package:personal_media_archiver/ui/pages/settings_page.dart';

/// 假 CookiesService — 可控 meta() 回傳
class _FakeCookiesService implements CookiesService {
  _FakeCookiesService({this.metaResult});

  final CookiesMeta? metaResult;

  @override
  Future<CookiesMeta?> meta() async => metaResult;

  @override
  Future<bool> exists() async => metaResult != null;

  @override
  Future<String?> path() async => metaResult != null ? '/fake/cookies.txt' : null;

  @override
  Future<CookiesMeta> import(File src) async =>
      throw UnimplementedError('not used in widget test');

  @override
  Future<CookiesMeta> importFromContent(String content) async =>
      throw UnimplementedError('not used in widget test');

  @override
  Future<void> remove() async {}

  @override
  bool isExpiring(CookiesMeta m) =>
      DateTime.now().difference(m.importedAt).inDays > 150;
}

Widget makeApp(CookiesService fake) {
  return ProviderScope(
    overrides: [cookiesServiceProvider.overrideWithValue(fake)],
    child: const MaterialApp(home: SettingsPage()),
  );
}

Future<void> setLargeViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void stubYtdlChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.pma/ytdl'),
    (call) async {
      if (call.method == 'version') return 'mock-version';
      if (call.method == 'init') return true;
      return null;
    },
  );
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dev.pma/ytdl'), null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsPage cookies tile', () {
    testWidgets('未匯入態：顯示「未匯入」+ 匯入 PopupMenuButton', (tester) async {
      await setLargeViewport(tester);
      stubYtdlChannel();
      await tester.pumpWidget(makeApp(_FakeCookiesService(metaResult: null)));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('YouTube cookies'), findsOneWidget);
      expect(find.textContaining('未匯入'), findsOneWidget);
      // 未匯入態：trailing 是 PopupMenuButton（智慧匯入 / 從檔案匯入兩選項）
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('已匯入態：顯示 domain count 跟 PopupMenuButton', (tester) async {
      await setLargeViewport(tester);
      stubYtdlChannel();
      final fake = _FakeCookiesService(
        metaResult: CookiesMeta(
          importedAt: DateTime(2026, 5, 16, 14, 30),
          domainCount: 2,
          lineCount: 5,
          hasYouTube: true,
        ),
      );
      await tester.pumpWidget(makeApp(fake));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.textContaining('已匯入 2 domain'), findsOneWidget);
      expect(find.textContaining('2026-05-16'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    });

    testWidgets('過期態（>150 天）：subtitle 顯示警告', (tester) async {
      await setLargeViewport(tester);
      stubYtdlChannel();
      final fake = _FakeCookiesService(
        metaResult: CookiesMeta(
          importedAt: DateTime.now().subtract(const Duration(days: 200)),
          domainCount: 1,
          lineCount: 3,
          hasYouTube: true,
        ),
      );
      await tester.pumpWidget(makeApp(fake));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.textContaining('已超過 5 個月'), findsOneWidget);
    });
  });
}
