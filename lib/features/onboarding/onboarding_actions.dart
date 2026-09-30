import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/sync/sync_service.dart';

/// The draft the first-run builder opens on: an untitled rubric whose single
/// group ([groupTitle], weight 100) holds the teacher's first [objective].
/// Mode and grading scale follow the teacher's defaults.
Rubric firstRubricDraft({
  required String objective,
  required String groupTitle,
  required AppSettings settings,
  DateTime? now,
}) {
  final draft = Rubric.create(now: now);
  return draft.copyWith(
    mode: settings.defaultMode,
    scale: settings.defaultScale,
    groups: [
      RubricGroup.create(
        groupTitle,
        weight: 100,
      ).copyWith(objectives: [Objective.create(objective.trim())]),
    ],
  );
}

/// First-run actions, shared by the welcome pager and its sheet.
extension OnboardingActions on WidgetRef {
  /// Saves the first-rubric draft and returns its id for the builder route.
  Future<String> saveFirstRubric(String objective, String groupTitle) async {
    final draft = firstRubricDraft(
      objective: objective,
      groupTitle: groupTitle,
      settings: read(settingsProvider),
    );
    final saved = await read(rubricRepositoryProvider).save(draft);
    return saved.id;
  }

  /// Loads the demo classroom, then finishes onboarding (the router sends the
  /// teacher Home once the flag flips).
  Future<void> exploreSampleData() async {
    await bulkChange(
      read(syncServiceProvider),
      () => loadSampleData(read(databaseProvider)),
    );
    await completeOnboarding();
  }

  Future<void> completeOnboarding() =>
      read(settingsProvider.notifier)
          .update((s) => s.copyWith(onboardingComplete: true));
}
