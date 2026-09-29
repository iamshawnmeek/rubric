import 'package:rubric/data/database.dart';

// STUB — implemented by the home/onboarding leaf. The signature is the
// contract (Settings and Welcome both call it); keep it.

/// Loads a realistic demo classroom (courses, students, rubrics, assignments,
/// graded work, comment bank). Idempotent: calling it twice adds nothing new.
Future<void> loadSampleData(AppDatabase db) async {}
