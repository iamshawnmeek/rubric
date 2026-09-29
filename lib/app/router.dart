import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/app/shell.dart';
import 'package:rubric/features/assignments/assignment_page.dart';
import 'package:rubric/features/assignments/new_assignment_page.dart';
import 'package:rubric/features/classes/classes_page.dart';
import 'package:rubric/features/classes/course_page.dart';
import 'package:rubric/features/classes/roster_import_page.dart';
import 'package:rubric/features/classes/student_page.dart';
import 'package:rubric/features/gradebook/gradebook_page.dart';
import 'package:rubric/features/grading/grading_page.dart';
import 'package:rubric/features/home/home_page.dart';
import 'package:rubric/features/onboarding/welcome_page.dart';
import 'package:rubric/features/rubric_builder/rubric_builder_page.dart';
import 'package:rubric/features/rubrics/rubric_detail_page.dart';
import 'package:rubric/features/rubrics/rubric_library_page.dart';
import 'package:rubric/features/rubrics/template_gallery_page.dart';
import 'package:rubric/features/settings/about_page.dart';
import 'package:rubric/features/settings/backup_page.dart';
import 'package:rubric/features/settings/comment_bank_page.dart';
import 'package:rubric/features/settings/settings_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// A fade — the transition the v1 FadeInPage used between onboarding steps.
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      ),
    );

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild redirects when onboarding completes, without recreating the router.
  final onboarded = ValueNotifier<bool>(
    ref.read(settingsProvider).onboardingComplete,
  );
  ref
    ..listen(
      settingsProvider.select((s) => s.onboardingComplete),
      (_, next) => onboarded.value = next,
    )
    ..onDispose(onboarded.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final path = state.uri.path;
      final inFirstRun = path == Routes.welcome || path.startsWith('/build/');
      if (!onboarded.value && !inFirstRun) return Routes.welcome;
      if (onboarded.value && path == Routes.welcome) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.welcome,
        pageBuilder: (context, state) => _fade(state, const WelcomePage()),
      ),
      GoRoute(
        path: '/build/:rubricId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _fade(
          state,
          RubricBuilderPage(
            key: ValueKey(state.uri.toString()),
            rubricId: state.pathParameters['rubricId']!,
            step:
                BuilderStep.values
                    .asNameMap()[state.uri.queryParameters['step']] ??
                BuilderStep.objectives,
            firstRun: state.uri.queryParameters['firstRun'] == '1',
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.classes,
                builder: (context, state) => const ClassesPage(),
                routes: [
                  GoRoute(
                    path: ':courseId',
                    builder: (context, state) =>
                        CoursePage(courseId: state.pathParameters['courseId']!),
                    routes: [
                      GoRoute(
                        path: 'students/:studentId',
                        builder: (context, state) => StudentPage(
                          courseId: state.pathParameters['courseId']!,
                          studentId: state.pathParameters['studentId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'import',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => RosterImportPage(
                          courseId: state.pathParameters['courseId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'gradebook',
                        builder: (context, state) => GradebookPage(
                          courseId: state.pathParameters['courseId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'assignments/new',
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (context, state) => NewAssignmentPage(
                          courseId: state.pathParameters['courseId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'assignments/:assignmentId',
                        builder: (context, state) => AssignmentPage(
                          courseId: state.pathParameters['courseId']!,
                          assignmentId: state.pathParameters['assignmentId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'grade/:studentId',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) => GradingPage(
                              assignmentId:
                                  state.pathParameters['assignmentId']!,
                              studentId: state.pathParameters['studentId']!,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.rubrics,
                builder: (context, state) => const RubricLibraryPage(),
                routes: [
                  GoRoute(
                    path: 'templates',
                    builder: (context, state) => const TemplateGalleryPage(),
                  ),
                  GoRoute(
                    path: ':rubricId',
                    builder: (context, state) => RubricDetailPage(
                      rubricId: state.pathParameters['rubricId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsPage(),
                routes: [
                  GoRoute(
                    path: 'comments',
                    builder: (context, state) => const CommentBankPage(),
                  ),
                  GoRoute(
                    path: 'backup',
                    builder: (context, state) => const BackupPage(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
