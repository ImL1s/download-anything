import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/policy/source_policy.dart';

class AppSettings {
  const AppSettings({
    this.strictness = PolicyStrictness.balanced,
    this.maxConcurrent = 2,
  });

  final PolicyStrictness strictness;
  final int maxConcurrent;

  AppSettings copyWith({
    PolicyStrictness? strictness,
    int? maxConcurrent,
  }) {
    return AppSettings(
      strictness: strictness ?? this.strictness,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
    );
  }
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings());

  void setStrictness(PolicyStrictness s) {
    state = state.copyWith(strictness: s);
  }

  void setMaxConcurrent(int n) {
    state = state.copyWith(maxConcurrent: n.clamp(1, 6));
  }
}
