import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cookies/cookies_service.dart';
import '../../core/extractors/ytdlp_bridge.dart';
import '../../core/policy/source_policy.dart';
import '../../state/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _ytdlpVersion = '未初始化';
  CookiesMeta? _cookiesMeta;
  bool _cookiesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadCookies();
  }

  Future<void> _loadVersion() async {
    try {
      final v = await YtDlpBridge.instance.version();
      if (!mounted) return;
      setState(() => _ytdlpVersion = v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ytdlpVersion = '無法取得：$e');
    }
  }

  Future<void> _loadCookies() async {
    if (mounted) setState(() => _cookiesLoading = true);
    try {
      final meta = await ref.read(cookiesServiceProvider).meta();
      if (!mounted) return;
      setState(() {
        _cookiesMeta = meta;
        _cookiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cookiesMeta = null;
        _cookiesLoading = false;
      });
    }
  }

  Future<void> _updateYtdlp() async {
    setState(() => _ytdlpVersion = '更新中…');
    try {
      final res = await YtDlpBridge.instance.update();
      if (!mounted) return;
      setState(() => _ytdlpVersion = '${res.version} (${res.status})');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${res.status}：${res.version}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _ytdlpVersion = '更新失敗：$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新失敗：$e')),
      );
    }
  }

  /// 智慧匯入 flow：3-step onboarding → 跳 youtube.com（user 選 Firefox）→ 等 share intent 回來
  Future<void> _smartImportFromFirefox() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _SmartImportDialog(),
    );
    if (ok != true) return;
    if (!mounted) return;

    // launch youtube.com — Android chooser 會讓 user 選 Firefox（若已裝）
    try {
      await launchUrl(
        Uri.parse('https://www.youtube.com'),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已開啟瀏覽器。登入後用 cookies extension 「分享」回 PMA'),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('無法開啟瀏覽器：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _importCookies() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        dialogTitle: '選擇 cookies.txt',
      );
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final meta = await ref.read(cookiesServiceProvider).import(file);
      if (!mounted) return;
      setState(() => _cookiesMeta = meta);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已匯入 cookies：${meta.domainCount} domain'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on CookiesValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('匯入失敗：${e.message}'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('匯入失敗：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _removeCookies() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除 cookies'),
        content: const Text('確認移除已匯入的 YouTube cookies？之後 YouTube 下載可能會失敗。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(cookiesServiceProvider).remove();
    if (!mounted) return;
    setState(() => _cookiesMeta = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已刪除 cookies')),
    );
  }

  Widget _buildCookiesTile() {
    final IconData iconData = Symbols.key_rounded;
    String subtitleText;
    Widget? trailing;

    if (_cookiesLoading) {
      subtitleText = '讀取中…';
      trailing = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_cookiesMeta == null) {
      subtitleText = '未匯入 — YouTube 因 Google 反爬機制需 cookies 才能下載';
      // 兩個按鈕：智慧匯入（推薦，純手機）+ 從檔案匯入（PC 用戶 fallback）
      trailing = PopupMenuButton<String>(
        icon: const Icon(Symbols.add_rounded),
        tooltip: '匯入',
        onSelected: (v) {
          if (v == 'smart') _smartImportFromFirefox();
          if (v == 'file') _importCookies();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'smart',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.public_rounded, size: 20),
              title: Text('智慧匯入'),
              subtitle: Text('用 Firefox（推薦）'),
            ),
          ),
          PopupMenuItem(
            value: 'file',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Symbols.folder_open_rounded, size: 20),
              title: Text('從檔案匯入'),
              subtitle: Text('已有 cookies.txt'),
            ),
          ),
        ],
      );
    } else {
      final formatter = DateFormat('yyyy-MM-dd HH:mm');
      subtitleText =
          '已匯入 ${_cookiesMeta!.domainCount} domain，${formatter.format(_cookiesMeta!.importedAt)}';
      if (ref.read(cookiesServiceProvider).isExpiring(_cookiesMeta!)) {
        subtitleText += '\n⚠️ 已超過 5 個月，建議重新匯入';
      }
      trailing = PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'reimport') _importCookies();
          if (v == 'remove') _removeCookies();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'reimport', child: Text('重新匯入')),
          PopupMenuItem(value: 'remove', child: Text('刪除')),
        ],
      );
    }

    return ListTile(
      leading: Icon(iconData),
      title: const Text('YouTube cookies'),
      subtitle: Text(
        subtitleText,
        maxLines: subtitleText.contains('\n') ? 3 : 2,
      ),
      trailing: trailing,
      isThreeLine: subtitleText.contains('\n') || subtitleText.length > 40,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final downloadRoot = ref.watch(downloadRootProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _SectionHeader(title: '政策'),
          Card(
            child: Column(
              children: PolicyStrictness.values
                  .map(
                    (s) => RadioListTile<PolicyStrictness>(
                      value: s,
                      groupValue: settings.strictness,
                      onChanged: (v) {
                        if (v == null) return;
                        ref
                            .read(settingsProvider.notifier)
                            .setStrictness(v);
                      },
                      title: Text(_strictnessLabel(s)),
                      subtitle: Text(_strictnessDescription(s)),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '下載'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Symbols.workspaces_rounded),
                  title: const Text('並行下載數'),
                  subtitle: Text('目前：${settings.maxConcurrent}'),
                  trailing: SizedBox(
                    width: 140,
                    child: Slider(
                      value: settings.maxConcurrent.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '${settings.maxConcurrent}',
                      onChanged: (v) {
                        ref
                            .read(settingsProvider.notifier)
                            .setMaxConcurrent(v.toInt());
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                downloadRoot.when(
                  data: (dir) => ListTile(
                    leading: const Icon(Symbols.folder_rounded),
                    title: const Text('儲存位置'),
                    subtitle: Text(
                      dir.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  loading: () => const ListTile(
                    leading: Icon(Symbols.folder_rounded),
                    title: Text('儲存位置'),
                    subtitle: Text('讀取中…'),
                  ),
                  error: (e, _) => ListTile(
                    leading: const Icon(Symbols.folder_rounded),
                    title: const Text('儲存位置'),
                    subtitle: Text('錯誤：$e'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '擷取器'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Symbols.terminal_rounded),
                  title: const Text('yt-dlp 版本'),
                  subtitle: Text(_ytdlpVersion),
                  trailing: IconButton(
                    icon: const Icon(Symbols.refresh_rounded),
                    onPressed: _loadVersion,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Symbols.system_update_rounded),
                  title: const Text('檢查 yt-dlp 更新'),
                  subtitle: const Text('從 GitHub 下載最新版（網路）'),
                  onTap: _updateYtdlp,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '進階'),
          Card(
            child: _buildCookiesTile(),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: '關於'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Symbols.policy_rounded),
                  title: const Text('使用守則'),
                  subtitle: const Text('Apache-2.0 開源，不蒐集個人資料'),
                  onTap: () => _showLegal(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Symbols.info_rounded),
                  title: const Text('版本'),
                  subtitle: const Text('Personal Media Archiver 0.1.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Symbols.gavel_rounded),
                  title: const Text('開源授權'),
                  subtitle: const Text('Apache-2.0；包含 youtubedl-android (GPL-3.0)、yt-dlp (Unlicense)'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Personal Media Archiver',
                    applicationVersion: '0.1.0',
                    applicationLegalese:
                        '© 2026 PMA — Apache-2.0\n含 youtubedl-android (GPL-3.0)，發佈成品須以 GPL-3.0 散布',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _strictnessLabel(PolicyStrictness s) => switch (s) {
        PolicyStrictness.strict => '嚴格',
        PolicyStrictness.balanced => '平衡（推薦）',
        PolicyStrictness.permissive => '寬鬆',
      };

  String _strictnessDescription(PolicyStrictness s) => switch (s) {
        PolicyStrictness.strict => '僅允許明確直連媒體或已知社交平台',
        PolicyStrictness.balanced => '其他 URL 顯示警告，由使用者確認',
        PolicyStrictness.permissive => '其他 URL 也允許嘗試下載',
      };

  void _showLegal(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('使用守則'),
        content: const SingleChildScrollView(
          child: Text(
            '本工具僅供保存使用者已獲授權存取之媒體內容。\n\n'
            '不支援也不協助規避 DRM、付費牆、登入保護、驗證機制或其他來源網站的技術限制。\n\n'
            '使用者應自行確認其操作符合所在地法律、著作權規範及來源網站／服務條款。專案維護者不提供任何第三方內容授權保證。\n\n'
            'Cookies / token 僅保存於本機，可隨時清除。預設不啟用遙測，不蒐集使用者媒體或帳號資料。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我了解了'),
          ),
        ],
      ),
    );
  }
}

/// 3-step onboarding for 智慧匯入 (Firefox + cookies extension + share)
class _SmartImportDialog extends StatelessWidget {
  const _SmartImportDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Symbols.public_rounded, color: scheme.primary, size: 36),
      title: const Text('純手機智慧匯入'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '一次性設定。之後 cookies 過期重做 step 2-3 即可。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _StepRow(
            num: '1',
            title: '裝 Firefox + cookies.txt extension',
            body: '到 Play Store 裝 Firefox → 在 Firefox 內裝 cookies extension（addons.mozilla.org 搜「cookies.txt」）',
            icon: Symbols.download_rounded,
          ),
          const SizedBox(height: 12),
          _StepRow(
            num: '2',
            title: '在 Firefox 內登入 youtube.com',
            body: '稍後按「開始」會自動跳 youtube → 用你的 Google 帳號登入',
            icon: Symbols.login_rounded,
          ),
          const SizedBox(height: 12),
          _StepRow(
            num: '3',
            title: '匯出 cookies → 分享回 PMA',
            body: '點 extension → 「Export」→ Android 分享選單 → 選 PMA → 自動匯入完成',
            icon: Symbols.share_rounded,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          icon: const Icon(Symbols.open_in_browser_rounded, size: 18),
          label: const Text('開始'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.num,
    required this.title,
    required this.body,
    required this.icon,
  });
  final String num;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            num,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}
