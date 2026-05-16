import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models/policy_decision.dart';

class PolicyBanner extends StatelessWidget {
  const PolicyBanner({super.key, required this.decision});

  final PolicyDecision decision;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon, String label) = switch (decision.verdict) {
      PolicyVerdict.allow => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Symbols.check_circle_rounded,
          '允許下載',
        ),
      PolicyVerdict.warn => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Symbols.warning_rounded,
          '需要您確認',
        ),
      PolicyVerdict.block => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Symbols.block_rounded,
          '已被阻擋',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  decision.reason,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg),
                ),
                if (decision.suggestion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    decision.suggestion!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.85),
                        ),
                  ),
                ],
                if (decision.host.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    decision.host,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.7),
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
