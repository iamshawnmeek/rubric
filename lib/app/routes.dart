import 'package:rubric/features/rubric_builder/rubric_builder_page.dart';

/// Every location in the app. Build paths with these instead of string
/// literals so a route rename is a compile error, not a dead link.
abstract final class Routes {
  static const welcome = '/welcome';
  static const home = '/';
  static const classes = '/classes';
  static const rubrics = '/rubrics';
  static const templates = '/rubrics/templates';
  static const settings = '/settings';
  static const commentBank = '/settings/comments';
  static const backup = '/settings/backup';
  static const about = '/settings/about';

  static String course(String courseId) => '/classes/$courseId';
  static String student(String courseId, String studentId) =>
      '/classes/$courseId/students/$studentId';
  static String rosterImport(String courseId) => '/classes/$courseId/import';
  static String gradebook(String courseId) => '/classes/$courseId/gradebook';
  static String newAssignment(String courseId) =>
      '/classes/$courseId/assignments/new';
  static String assignment(String courseId, String assignmentId) =>
      '/classes/$courseId/assignments/$assignmentId';
  static String grade(String courseId, String assignmentId, String studentId) =>
      '/classes/$courseId/assignments/$assignmentId/grade/$studentId';

  static String rubric(String rubricId) => '/rubrics/$rubricId';

  /// [rubricId] `new` starts a fresh rubric.
  static String buildRubric(
    String rubricId, {
    BuilderStep step = BuilderStep.objectives,
    bool firstRun = false,
  }) => Uri(
    path: '/build/$rubricId',
    queryParameters: {'step': step.name, if (firstRun) 'firstRun': '1'},
  ).toString();
}
