/// 來源政策分類器產出的決策。
///
/// 三種等級對應 UI 行為：
/// * [PolicyVerdict.allow] — 允許下載，不顯示警示
/// * [PolicyVerdict.warn] — 顯示警告，要求使用者確認
/// * [PolicyVerdict.block] — 直接阻擋，不允許下載
enum PolicyVerdict { allow, warn, block }

class PolicyDecision {
  const PolicyDecision({
    required this.verdict,
    required this.reason,
    required this.host,
    this.suggestion,
  });

  final PolicyVerdict verdict;
  final String reason;
  final String host;
  final String? suggestion;

  bool get canDownload => verdict != PolicyVerdict.block;

  @override
  String toString() =>
      'PolicyDecision(verdict: $verdict, host: $host, reason: $reason)';
}
