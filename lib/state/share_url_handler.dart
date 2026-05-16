/// Pure logic for share URL handling — extracted from main_shell.dart for testability.
///
/// Mirrors Kotlin `isLikelySingleUrl` in MainActivity.kt so both sides agree on
/// what counts as a "URL share" (vs cookies file vs random text). Native side
/// is first-layer filter (avoid spamming the EventChannel); this Dart side is
/// defense-in-depth for the verdict → action mapping.
library;

import '../core/models/policy_decision.dart';
import '../core/policy/source_policy.dart';

/// Heuristic: trimmed content looks like a single URL we should route to share_url channel.
/// Rules (mirror of Kotlin):
///   - length ≤ 2048
///   - no newlines / whitespace (single token)
///   - starts with http:// or https://
///   - URI.parse has non-empty host
bool isLikelyShareUrl(String content) {
  if (content.length > 2048) return false;
  if (content.contains('\n') || content.contains(' ') || content.contains('\t')) {
    return false;
  }
  if (!content.startsWith('http://') && !content.startsWith('https://')) {
    return false;
  }
  try {
    final uri = Uri.parse(content);
    return uri.host.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Sum type for the three possible actions on a share-URL intent.
sealed class ShareUrlAction {
  const ShareUrlAction(this.decision);
  final PolicyDecision decision;
}

/// Policy verdict == ALLOW → auto-enqueue download + jump to queue tab.
class ShareUrlAutoEnqueue extends ShareUrlAction {
  const ShareUrlAutoEnqueue(this.url, super.decision);
  final String url;
}

/// Policy verdict == WARN → prefill home page textfield, require user consent.
class ShareUrlNeedsConsent extends ShareUrlAction {
  const ShareUrlNeedsConsent(this.url, super.decision);
  final String url;
}

/// Policy verdict == BLOCK → reject, SnackBar with reason.
class ShareUrlBlocked extends ShareUrlAction {
  const ShareUrlBlocked(super.decision);
}

/// Map URL + SourcePolicy → action.
ShareUrlAction classifyShare(String url, SourcePolicy policy) {
  final decision = policy.classify(url);
  switch (decision.verdict) {
    case PolicyVerdict.block:
      return ShareUrlBlocked(decision);
    case PolicyVerdict.warn:
      return ShareUrlNeedsConsent(url, decision);
    case PolicyVerdict.allow:
      return ShareUrlAutoEnqueue(url, decision);
  }
}
