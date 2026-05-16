import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../state/providers.dart';
import '../../state/task_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/task_card.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskControllerProvider);
    final hasTerminal = tasks.any((t) => t.task.isTerminal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('下載佇列'),
        actions: [
          if (hasTerminal)
            IconButton(
              tooltip: '清除已完成',
              icon: const Icon(Symbols.cleaning_services_rounded),
              onPressed: () =>
                  ref.read(taskControllerProvider.notifier).clearTerminal(),
            ),
        ],
      ),
      body: tasks.isEmpty
          ? const EmptyState(
              icon: Symbols.inbox_rounded,
              title: '目前沒有下載任務',
              subtitle: '回到首頁貼上 URL 即可建立任務',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final ts = tasks[i];
                return TaskCard(
                  key: ValueKey(ts.task.id),
                  task: ts.task,
                  isYtdlp: ts.mode == TaskMode.ytdlp,
                  onCancel: () =>
                      ref.read(taskControllerProvider.notifier).cancel(ts.task.id),
                  onRemove: () =>
                      ref.read(taskControllerProvider.notifier).remove(ts.task.id),
                );
              },
            ),
    );
  }
}
