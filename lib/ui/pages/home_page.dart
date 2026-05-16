import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models/policy_decision.dart';
import '../../state/providers.dart';
import '../widgets/policy_banner.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _controller = TextEditingController();
  PolicyDecision? _decision;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _classify(String input) {
    final policy = ref.read(policyProvider);
    setState(() {
      _decision = input.trim().isEmpty ? null : policy.classify(input);
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    _controller.text = text;
    _classify(text);
  }

  Future<void> _startDownload() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _decision == null || !_decision!.canDownload) return;
    await ref.read(taskControllerProvider.notifier).enqueue(url);
    if (!mounted) return;
    _controller.clear();
    setState(() => _decision = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已加入下載佇列'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  bool _isYouTubeHost(String host) {
    final lc = host.toLowerCase();
    return lc.endsWith('youtube.com') ||
        lc.endsWith('youtu.be') ||
        lc.endsWith('youtube-nocookie.com');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDownload =
        _decision != null && _decision!.canDownload && _controller.text.trim().isNotEmpty;
    final cookiesExistsAsync = ref.watch(cookiesExistsProvider);
    final isYouTube = _decision != null && _isYouTubeHost(_decision!.host);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Media Archiver'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.info_rounded),
            tooltip: '關於本工具',
            onPressed: () => _showAbout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '貼上媒體網址',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '支援直連媒體與多數公開社交平台。\n本工具不會繞過 DRM 或付費牆。',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    maxLines: 3,
                    minLines: 1,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: 'https://...',
                      prefixIcon: const Icon(Symbols.link_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Symbols.cancel_rounded),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _decision = null);
                              },
                            ),
                    ),
                    onChanged: _classify,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _startDownload(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Symbols.content_paste_rounded),
                          label: const Text('從剪貼簿貼上'),
                          onPressed: _pasteFromClipboard,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Symbols.download_rounded),
                          label: const Text('開始下載'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.tertiary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onTertiary,
                          ),
                          onPressed: canDownload ? _startDownload : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_decision != null) PolicyBanner(decision: _decision!),
          // YouTube + 未匯入 cookies hint：避免 user 撞牆才知道要 cookies
          if (isYouTube && cookiesExistsAsync.value == false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.key_rounded,
                      color: scheme.onTertiaryContainer, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YouTube 通常需要 cookies 才能下載',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '建議先至「設定 → 進階 → YouTube cookies」匯入瀏覽器 cookies.txt，否則 yt-dlp 會被擋下。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onTertiaryContainer,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Symbols.settings_rounded, size: 16),
                            label: const Text('前往設定'),
                            onPressed: () {
                              ref.read(selectedTabProvider.notifier).state = 3;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Symbols.verified_user_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '使用守則',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const _Bullet('本工具僅供保存使用者已獲授權存取之媒體內容。'),
                  const _Bullet('不支援 DRM、付費牆、登入保護或其他技術限制的內容。'),
                  const _Bullet('Cookies / token 僅保存於本機，預設不啟用遙測。'),
                  const _Bullet('使用者需自行確認操作符合所在地法律與來源服務條款。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Personal Media Archiver',
      applicationVersion: '0.1.0',
      applicationLegalese:
          '© 2026 PMA — Apache-2.0 License\n本工具僅供保存合法存取之媒體，不繞過 DRM。',
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
