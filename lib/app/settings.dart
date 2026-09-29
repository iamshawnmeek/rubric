import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. Small, flat, and read synchronously after startup.
class AppSettings {
  const new({
    this.onboardingComplete = false,
    this.teacherName = '',
    this.defaultMode = GradingMode.simple,
    this.defaultScale = GradingScale.standard,
    this.decimals = 1,
    this.haptics = true,
    this.latePenaltyPercent = 10,
    this.showLetterGrades = true,
  });

  factory fromJson(Map<String, dynamic> json) => AppSettings(
    onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    teacherName: json['teacherName'] as String? ?? '',
    defaultMode: GradingMode.values.byName(
      json['defaultMode'] as String? ?? GradingMode.simple.name,
    ),
    defaultScale: json['defaultScale'] == null
        ? GradingScale.standard
        : GradingScale.fromJson(json['defaultScale'] as Map<String, dynamic>),
    decimals: json['decimals'] as int? ?? 1,
    haptics: json['haptics'] as bool? ?? true,
    latePenaltyPercent: (json['latePenaltyPercent'] as num?)?.toDouble() ?? 10,
    showLetterGrades: json['showLetterGrades'] as bool? ?? true,
  );

  final bool onboardingComplete;
  final String teacherName;
  final GradingMode defaultMode;
  final GradingScale defaultScale;

  /// Decimal places shown on percentages.
  final int decimals;
  final bool haptics;

  /// Default deduction applied when a paper is marked late.
  final double latePenaltyPercent;
  final bool showLetterGrades;

  AppSettings copyWith({
    bool? onboardingComplete,
    String? teacherName,
    GradingMode? defaultMode,
    GradingScale? defaultScale,
    int? decimals,
    bool? haptics,
    double? latePenaltyPercent,
    bool? showLetterGrades,
  }) => AppSettings(
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    teacherName: teacherName ?? this.teacherName,
    defaultMode: defaultMode ?? this.defaultMode,
    defaultScale: defaultScale ?? this.defaultScale,
    decimals: decimals ?? this.decimals,
    haptics: haptics ?? this.haptics,
    latePenaltyPercent: latePenaltyPercent ?? this.latePenaltyPercent,
    showLetterGrades: showLetterGrades ?? this.showLetterGrades,
  );

  Map<String, dynamic> toJson() => {
    'onboardingComplete': onboardingComplete,
    'teacherName': teacherName,
    'defaultMode': defaultMode.name,
    'defaultScale': defaultScale.toJson(),
    'decimals': decimals,
    'haptics': haptics,
    'latePenaltyPercent': latePenaltyPercent,
    'showLetterGrades': showLetterGrades,
  };
}

/// Overridden in main() with the instance loaded before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider'),
);

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'settings.v1';

  @override
  AppSettings build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // A corrupt blob must not brick the app; fall back to defaults.
      return const AppSettings();
    }
  }

  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(state.toJson()));
  }
}
