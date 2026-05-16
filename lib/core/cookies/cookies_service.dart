import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CookiesMeta {
  final DateTime importedAt;
  final int domainCount;
  final int lineCount;
  final bool hasYouTube;
  const CookiesMeta({
    required this.importedAt,
    required this.domainCount,
    required this.lineCount,
    required this.hasYouTube,
  });
}

class CookiesValidationException implements Exception {
  final String message;
  CookiesValidationException(this.message);
  @override
  String toString() => 'CookiesValidationException: $message';
}

class CookiesService {
  Future<String> _cookiesPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/ytdlp/youtube.cookies.txt';
  }

  /// 驗證 src 為合法 Netscape cookies + 至少一行 youtube.com domain，
  /// 然後複製到 `<docs>/ytdlp/youtube.cookies.txt` 取代舊檔，回傳 meta。
  /// 失敗 throw CookiesValidationException。
  Future<CookiesMeta> import(File src) async {
    final content = await src.readAsString();
    return importFromContent(content);
  }

  /// 從 raw cookies content (Netscape format string) 直接匯入。
  /// 用途：Android share intent receiver / clipboard / Firefox extension share。
  Future<CookiesMeta> importFromContent(String content) async {
    // 驗證 Netscape cookies 格式
    if (!content.substring(0, content.length < 200 ? content.length : 200)
        .contains('# Netscape HTTP Cookie File')) {
      throw CookiesValidationException('檔案不是 Netscape cookies 格式');
    }

    final lines = content.split('\n');

    // 解析 cookie 行
    final domainSet = <String>{};
    int lineCount = 0;
    bool hasYouTube = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // Netscape format：`#HttpOnly_<domain>\t...` 是 HttpOnly cookie row 不是 comment
      // YouTube auth cookies (SID/HSID/SSID/SAPISID) 通常都是 HttpOnly，
      // 跳過 #HttpOnly_ prefix 解析後續欄位
      if (trimmed.startsWith('#HttpOnly_')) {
        trimmed = trimmed.substring('#HttpOnly_'.length);
      } else if (trimmed.startsWith('#')) {
        continue; // real comment
      }

      lineCount++;
      final parts = trimmed.split('\t');
      if (parts.isNotEmpty) {
        final domain = parts[0];
        domainSet.add(domain);
        if (domain == '.youtube.com' || domain == 'youtube.com') {
          hasYouTube = true;
        }
      }
    }

    if (!hasYouTube) {
      throw CookiesValidationException('檔案不含 youtube.com cookies');
    }

    // 寫入目標路徑（不用 src.copy；直接寫 content 給 native channel / clipboard 流程）
    final destPath = await _cookiesPath();
    final destDir = Directory(destPath.substring(0, destPath.lastIndexOf('/')));
    await destDir.create(recursive: true);
    await File(destPath).writeAsString(content);

    return CookiesMeta(
      importedAt: DateTime.now(),
      domainCount: domainSet.length,
      lineCount: lineCount,
      hasYouTube: hasYouTube,
    );
  }

  /// 是否已匯入 cookies file
  Future<bool> exists() async {
    final path = await _cookiesPath();
    return File(path).exists();
  }

  /// 已匯入 file 的絕對路徑，未匯入則 null
  Future<String?> path() async {
    final p = await _cookiesPath();
    final file = File(p);
    if (await file.exists()) return p;
    return null;
  }

  /// 刪除已匯入 cookies file（若存在）
  Future<void> remove() async {
    final p = await _cookiesPath();
    final file = File(p);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// cookies 是否已老化（>5 個月）；UI 用來顯示「建議重新匯入」提示
  bool isExpiring(CookiesMeta meta) =>
      DateTime.now().difference(meta.importedAt).inDays > 150;

  /// 讀現有 cookies 計算 meta，未匯入回 null
  Future<CookiesMeta?> meta() async {
    final p = await _cookiesPath();
    final file = File(p);
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    final lines = content.split('\n');
    final domainSet = <String>{};
    int lineCount = 0;
    bool hasYouTube = false;

    for (final line in lines) {
      var trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#HttpOnly_')) {
        trimmed = trimmed.substring('#HttpOnly_'.length);
      } else if (trimmed.startsWith('#')) {
        continue;
      }

      lineCount++;
      final parts = trimmed.split('\t');
      if (parts.isNotEmpty) {
        final domain = parts[0];
        domainSet.add(domain);
        if (domain == '.youtube.com' || domain == 'youtube.com') {
          hasYouTube = true;
        }
      }
    }

    final stat = await file.stat();

    return CookiesMeta(
      importedAt: stat.modified,
      domainCount: domainSet.length,
      lineCount: lineCount,
      hasYouTube: hasYouTube,
    );
  }
}
