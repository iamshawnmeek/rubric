/// The synced tables in the order deleting an account must empty them:
/// children before the rows they reference, so no foreign key ever points at
/// a deleted row. It is `syncTables` reversed (a test holds them together);
/// it is spelled out here, free of Flutter and drift, so the post-deploy smoke
/// test (tool/deploy/smoke.dart) deletes in the very same order as the app.
const accountDeletionOrder = [
  'evaluations',
  'assignments',
  'students',
  'courses',
  'comment_snippets',
  'rubrics',
];

/// The auth table holding the teacher's own row, deleted last.
const accountTable = 'users';
