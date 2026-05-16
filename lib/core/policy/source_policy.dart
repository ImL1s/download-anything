import '../models/policy_decision.dart';

/// 來源政策分類器。
///
/// 純函式設計，方便單元測試。輸入 URL 字串，輸出 [PolicyDecision]。
/// 政策邊界：
///   - BLOCK：DRM/付費內容平台
///   - ALLOW (direct)：直連媒體檔案
///   - ALLOW (extractor)：yt-dlp 支援的公開社交平台
///   - WARN：其餘無法辨識者
class SourcePolicy {
  const SourcePolicy({this.strictness = PolicyStrictness.balanced});

  final PolicyStrictness strictness;

  /// 已知會被 BLOCK 的網域：DRM / 第三方授權嚴格服務。
  static const _blockedHostSuffixes = <String>[
    'netflix.com',
    'disneyplus.com',
    'hulu.com',
    'primevideo.com',
    'hbomax.com',
    'max.com',
    'paramountplus.com',
    'peacocktv.com',
    'crunchyroll.com',
    'iq.com',
    'iqiyi.com',
    'spotify.com',
    'music.apple.com',
    'tidal.com',
    'deezer.com',
    'audible.com',
    'kkbox.com',
    'kkstream.com',
    'kktv.me',
    'litv.tv',
    'friday.tw',
    'myvideo.net.tw',
    'line.me/tv',
    // 補：台灣 OTT / 串流授權平台（皆需付費或 DRM 保護）
    'viu.com',
    'viu.tv',
    'catchplay.com',
    'hamivideo.hinet.net',
    'vidol.tv',
    'pubu.com.tw',
    'bookwalker.com.tw',
    'iqiyi.com.tw',
    'mod.cht.com.tw',
  ];

  /// yt-dlp 支援的公開社交平台（精選）。
  ///
  /// 這些站點的「公開內容」會走 yt-dlp 擷取流程；登入受保護內容需要使用者自行
  /// 提供 cookies 並由產品邊界另行管控（MVP 不支援）。
  static const _ytdlpHostSuffixes = <String>[
    'youtube.com',
    'youtu.be',
    'm.youtube.com',
    'music.youtube.com',
    'twitter.com',
    'x.com',
    't.co',
    'threads.net',
    'threads.com',
    'instagram.com',
    'facebook.com',
    'fb.watch',
    'tiktok.com',
    'douyin.com',
    'bilibili.com',
    'b23.tv',
    'twitch.tv',
    'clips.twitch.tv',
    'vimeo.com',
    'reddit.com',
    'redd.it',
    'soundcloud.com',
    'dailymotion.com',
    'pinterest.com',
    'streamable.com',
    'odysee.com',
    'rumble.com',
    'bitchute.com',
    'lbry.tv',
    'archive.org',
    'ted.com',
    'tv.naver.com',
    'weibo.com',
    'kuaishou.com',
    'xiaohongshu.com',
    'tumblr.com',
    'imgur.com',
    'twitch.tv',
  ];

  static const _allowedMediaExtensions = <String>[
    '.mp4',
    '.m4v',
    '.mov',
    '.webm',
    '.mkv',
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus',
  ];

  PolicyDecision classify(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const PolicyDecision(
        verdict: PolicyVerdict.block,
        reason: '請輸入網址',
        host: '',
      );
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return const PolicyDecision(
        verdict: PolicyVerdict.block,
        reason: '不是有效的網址',
        host: '',
      );
    }

    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return PolicyDecision(
        verdict: PolicyVerdict.block,
        reason: '只支援 http/https 來源',
        host: uri.host,
      );
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) {
      return const PolicyDecision(
        verdict: PolicyVerdict.block,
        reason: '網址沒有主機名',
        host: '',
      );
    }

    // 1. BLOCK：DRM / 第三方授權嚴格服務
    for (final suffix in _blockedHostSuffixes) {
      if (_hostMatches(host, suffix)) {
        return PolicyDecision(
          verdict: PolicyVerdict.block,
          reason: '此來源屬於 DRM 保護或第三方授權內容，本工具不支援。',
          host: host,
          suggestion: '請改用您已合法持有的本機檔案或直連媒體 URL。',
        );
      }
    }

    // 2. ALLOW（extractor）：yt-dlp 支援的公開社交平台
    for (final suffix in _ytdlpHostSuffixes) {
      if (_hostMatches(host, suffix)) {
        return PolicyDecision(
          verdict: PolicyVerdict.allow,
          reason: '社交平台公開內容，將以 yt-dlp 擷取。',
          host: host,
          suggestion: '請自行確認來源合法且符合來源服務條款。',
        );
      }
    }

    // 3. ALLOW（direct）：副檔名屬已知媒體格式
    final lowerPath = uri.path.toLowerCase();
    for (final ext in _allowedMediaExtensions) {
      if (lowerPath.endsWith(ext)) {
        return PolicyDecision(
          verdict: PolicyVerdict.allow,
          reason: '直連媒體檔案（${ext.substring(1).toUpperCase()}）。',
          host: host,
        );
      }
    }

    // 4. 其他：依嚴格度處理
    switch (strictness) {
      case PolicyStrictness.strict:
        return PolicyDecision(
          verdict: PolicyVerdict.block,
          reason: '嚴格模式：僅允許明確的直連媒體 URL 或已知社交平台。',
          host: host,
          suggestion: '可在設定改為平衡模式以允許其他 URL。',
        );
      case PolicyStrictness.balanced:
        return PolicyDecision(
          verdict: PolicyVerdict.warn,
          reason: '未知來源，將嘗試以 yt-dlp 擷取，可能失敗。',
          host: host,
          suggestion: '請自行確認來源合法。',
        );
      case PolicyStrictness.permissive:
        return PolicyDecision(
          verdict: PolicyVerdict.warn,
          reason: '寬鬆模式：未辨識的 URL，下載可能失敗。',
          host: host,
        );
    }
  }

  /// 判斷一個 URL 是否該走 yt-dlp 路徑（vs 直連下載）。
  bool requiresExtractor(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      for (final suffix in _ytdlpHostSuffixes) {
        if (_hostMatches(host, suffix)) return true;
      }
      // 直連媒體優先：副檔名匹配就走 dio
      final lowerPath = uri.path.toLowerCase();
      for (final ext in _allowedMediaExtensions) {
        if (lowerPath.endsWith(ext)) return false;
      }
      // 其他：預設走 yt-dlp（它支援的站點多）
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _hostMatches(String host, String suffix) {
    if (host == suffix) return true;
    if (host.endsWith('.$suffix')) return true;
    // 處理路徑型 suffix（如 line.me/tv）
    if (suffix.contains('/')) {
      final parts = suffix.split('/');
      final h = parts.first;
      if (host == h || host.endsWith('.$h')) return true;
    }
    return false;
  }
}

enum PolicyStrictness { strict, balanced, permissive }
