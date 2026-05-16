import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/models/download_task.dart';
import '../../state/providers.dart';

class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onCancel,
    required this.onRemove,
    this.isYtdlp = false,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final bool isYtdlp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = _statusVisual(scheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (task.isTerminal)
                  IconButton(
                    icon: const Icon(Symbols.delete_outline_rounded, size: 20),
                    tooltip: '從清單移除',
                    onPressed: onRemove,
                  )
                else
                  IconButton(
                    icon: const Icon(Symbols.cancel_rounded, size: 20),
                    tooltip: '取消',
                    onPressed: onCancel,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              task.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            if (task.status == DownloadStatus.running ||
                task.status == DownloadStatus.queued)
              _ProgressRow(task: task)
            else
              _StatusRow(label: label, color: color, task: task),
            if (isYtdlp) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Symbols.extension_rounded,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'yt-dlp 擷取',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
            if (task.errorMessage != null) ...[
              const SizedBox(height: 8),
              if (task.needsCookies) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Symbols.key_rounded, size: 16),
                    label: const Text('匯入 cookies'),
                    onPressed: () {
                      ref.read(selectedTabProvider.notifier).state = 3;
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  task.errorMessage!.replaceFirst('[NEEDS_COOKIES] ', ''),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                ),
              ] else
                Text(
                  task.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _statusVisual(ColorScheme scheme) {
    switch (task.status) {
      case DownloadStatus.queued:
        return (Symbols.schedule_rounded, scheme.onSurfaceVariant, '排隊中');
      case DownloadStatus.running:
        return (Symbols.downloading_rounded, scheme.primary, '下載中');
      case DownloadStatus.paused:
        return (Symbols.pause_circle_rounded, scheme.secondary, '已暫停');
      case DownloadStatus.completed:
        return (Symbols.check_circle_rounded, scheme.primary, '已完成');
      case DownloadStatus.failed:
        return (Symbols.error_rounded, scheme.error, '失敗');
      case DownloadStatus.canceled:
        return (Symbols.cancel_rounded, scheme.onSurfaceVariant, '已取消');
    }
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final progress = task.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress == 0 ? null : progress,
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _bytesLabel(task),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _bytesLabel(DownloadTask t) {
    if (t.totalBytes <= 0) return '${_human(t.receivedBytes)} / 未知';
    return '${_human(t.receivedBytes)} / ${_human(t.totalBytes)}';
  }

  String _human(int bytes) {
    if (bytes < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.color,
    required this.task,
  });
  final String label;
  final Color color;
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (task.totalBytes > 0)
          Text(
            _human(task.totalBytes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  String _human(int bytes) {
    if (bytes < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
