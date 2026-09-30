import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/data/sample_data.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/home/home_dashboard.dart';
import 'package:rubric/features/home/home_providers.dart';
import 'package:rubric/features/sync/sync_status_view.dart';
import 'package:rubric/l10n/l10n.dart';
import 'package:rubric/sync/sync_service.dart';

/// Tab 1: what needs grading, what is due next, and a way into everything.
class HomePage extends ConsumerStatefulWidget {
  const new({super.key});

  /// Content stops growing here so tablets do not get stretched cards.
  static const maxContentWidth = 720.0;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _loadingSample = false;

  Future<void> _loadSample() async {
    final l = context.l10n;
    setState(() => _loadingSample = true);
    try {
      await bulkChange(
        ref.read(syncServiceProvider),
        () => loadSampleData(ref.read(databaseProvider)),
      );
      if (mounted) showRubricSnack(context, l.homeSampleDataLoaded);
    } on Object {
      if (mounted) showRubricSnack(context, l.homeSampleDataError);
    } finally {
      if (mounted) setState(() => _loadingSample = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final name = ref.watch(settingsProvider.select((s) => s.teacherName));
    final period = dayPeriodOf(ref.watch(homeClockProvider)()).name;
    final dashboard = ref.watch(homeDashboardProvider);

    return RubricPage(
      title: name.trim().isEmpty
          ? l.homeGreeting(period)
          : l.homeGreetingNamed(period, name.trim()),
      showBack: false,
      actions: const [SyncIndicator()],
      children: [
        _Readable(
          child: AsyncView(
            value: dashboard,
            data: (data) => data.isEmpty
                ? _EmptyHome(
                    loadingSample: _loadingSample,
                    onLoadSample: _loadSample,
                  )
                : _Dashboard(data: data),
          ),
        ),
      ],
    );
  }
}

/// Centres [child] and caps its width at [HomePage.maxContentWidth].
class _Readable extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: HomePage.maxContentWidth),
        child: child,
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const new({required this.data});

  final HomeDashboard data;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${data.courses.length}',
                label: l.homeStatClasses(data.courses.length),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: StatTile(
                value: '${data.studentCount}',
                label: l.homeStatStudents(data.studentCount),
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: StatTile(
                value: '${data.gradedThisWeek}',
                label: l.homeStatGradedThisWeek,
              ),
            ),
          ],
        ),
        SectionLabel(l.homeToGradeSection),
        if (data.toGrade.isEmpty && data.courses.isEmpty)
          _Notice(title: l.homeNoClassesTitle, message: l.homeNoClassesMessage)
        else if (data.toGrade.isEmpty)
          _Notice(title: l.homeAllCaughtUp, message: l.homeAllCaughtUpMessage)
        else
          for (final item in data.toGrade) ...[
            _QueueCard(item: item),
            const SizedBox(height: Insets.sm),
          ],
        if (data.comingUp.isNotEmpty) ...[
          SectionLabel(l.homeComingUpSection),
          for (final item in data.comingUp) ...[
            _ComingUpCard(item: item),
            const SizedBox(height: Insets.sm),
          ],
        ],
        if (data.recentRubrics.isNotEmpty) ...[
          SectionLabel(
            l.homeRecentRubricsSection,
            trailing: TextButton(
              onPressed: () => context.go(Routes.rubrics),
              child: Text(l.homeSeeAll),
            ),
          ),
          for (final rubric in data.recentRubrics) ...[
            RubricCard(
              cardHintText: _rubricHint(context, rubric),
              cardTitleText: rubric.title.trim().isEmpty
                  ? l.homeUntitledRubric
                  : rubric.title,
              titleMaxLines: 2,
              onTap: () => context.go(Routes.rubric(rubric.id)),
              trailing: const _Chevron(),
            ),
            const SizedBox(height: Insets.sm),
          ],
        ],
        SectionLabel(l.homeQuickActionsSection),
        _QuickActions(courses: data.courses),
      ],
    );
  }

  static String _rubricHint(BuildContext context, Rubric rubric) {
    final l = context.l10n;
    final parts = [
      if (rubric.subject.trim().isNotEmpty) rubric.subject.trim(),
      l.homeRubricSummary(rubric.mode.name, rubric.objectives.length),
    ];
    return parts.join(' · ');
  }
}

/// "Due Thu, Oct 2", "Due today", "No due date".
String _dueLabel(BuildContext context, DateTime? due, DateTime now) {
  final l = context.l10n;
  if (due == null) return l.homeNoDueDate;
  final days = DateTime(
    due.year,
    due.month,
    due.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return l.homeDueToday;
  if (days == 1) return l.homeDueTomorrow;
  final date = DateFormat.MMMEd(Localizations.localeOf(context).toLanguageTag())
      .format(due);
  return days < 0 ? l.homeWasDue(date) : l.homeDueOn(date);
}

String _courseLabel(Course course) =>
    [course.name, course.section].where((s) => s.trim().isNotEmpty).join(' · ');

/// One assignment waiting on the teacher: progress bar, what is left, and a
/// tap straight into it.
class _QueueCard extends ConsumerWidget {
  const new({required this.item});

  final AssignmentProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final now = ref.watch(homeClockProvider)();
    final due = _dueLabel(context, item.assignment.dueDate, now);
    final course = _courseLabel(item.course);
    final progress = l.homeToGradeProgress(item.done, item.total);
    final remaining = l.homeToGradeRemaining(item.remaining);

    return Semantics(
      button: true,
      label: '$course, ${item.assignment.title}, $due, $progress, $remaining',
      excludeSemantics: true,
      child: Material(
        color: primaryCard,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: () =>
              context.go(Routes.assignment(item.course.id, item.assignment.id)),
          child: Padding(
            padding: Insets.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CardHint(
                            course,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: Insets.xs),
                          CardTitle(
                            item.assignment.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.remaining}',
                          style: RubricTextStyles.statValue.copyWith(
                            color: accent,
                          ),
                        ),
                        Text(
                          l.homeToGradeLeft,
                          style: RubricTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                RubricProgressBar(value: item.progress),
                const SizedBox(height: Insets.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(progress, style: RubricTextStyles.caption),
                    ),
                    Text(due, style: RubricTextStyles.caption),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingUpCard extends ConsumerWidget {
  const new({required this.item});

  final AssignmentProgress item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(homeClockProvider)();
    return RubricCard(
      cardHintText: _dueLabel(context, item.assignment.dueDate, now),
      cardTitleText: item.assignment.title,
      titleMaxLines: 2,
      color: primaryDark,
      footer: Text(_courseLabel(item.course), style: RubricTextStyles.caption),
      onTap: () =>
          context.go(Routes.assignment(item.course.id, item.assignment.id)),
      trailing: const _Chevron(),
    );
  }
}

class _Chevron extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const FaIcon(
      FontAwesomeIcons.chevronRight,
      color: primaryLight,
      size: 18,
    );
  }
}

/// A quiet card for "nothing here" inside a section.
class _Notice extends StatelessWidget {
  const new({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Insets.card,
      decoration: BoxDecoration(color: primaryDark, borderRadius: Corners.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: RubricTextStyles.listTitle),
          const SizedBox(height: 4),
          Text(message, style: RubricTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const new({required this.courses});

  final List<Course> courses;

  Future<void> _newAssignment(BuildContext context) async {
    if (courses.length == 1) {
      await context.push(Routes.newAssignment(courses.single.id));
      return;
    }
    final courseId = await showRubricSheet<String>(
      context: context,
      child: RubricSheet(
        title: context.l10n.homePickClassTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final course in courses) ...[
              Builder(
                builder: (context) => RubricCard(
                  cardHintText: course.section,
                  cardTitleText: course.name,
                  onTap: () => Navigator.of(context).pop(course.id),
                ),
              ),
              const SizedBox(height: Insets.sm),
            ],
          ],
        ),
      ),
    );
    if (courseId != null && context.mounted) {
      await context.push(Routes.newAssignment(courseId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final actions = [
      _QuickAction(
        icon: FontAwesomeIcons.tableList,
        label: l.homeNewRubric,
        onTap: () => context.push(Routes.buildRubric('new')),
      ),
      _QuickAction(
        icon: FontAwesomeIcons.users,
        label: l.homeNewClass,
        onTap: () => context.go(Routes.classes),
      ),
      if (courses.isNotEmpty)
        _QuickAction(
          icon: FontAwesomeIcons.filePen,
          label: l.homeNewAssignment,
          onTap: () => _newAssignment(context),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, action) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: Insets.sm),
          Expanded(child: action),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onTap});

  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: primaryCard,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(Insets.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FaIcon(icon, color: accent, size: 22),
                const SizedBox(height: Insets.sm),
                Text(
                  label,
                  style: RubricTextStyles.listTitle.copyWith(fontSize: 17),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A brand-new teacher: say what the app is for and offer three ways in.
class _EmptyHome extends StatelessWidget {
  const new({required this.loadingSample, required this.onLoadSample});

  final bool loadingSample;
  final VoidCallback onLoadSample;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(title: l.homeEmptyTitle, message: l.homeEmptyMessage),
        RubricCard(
          cardHintText: l.homeEmptyCreateClassHint,
          cardTitleText: l.homeEmptyCreateClass,
          onTap: () => context.go(Routes.classes),
          trailing: const _Chevron(),
        ),
        const SizedBox(height: Insets.sm),
        RubricCard(
          cardHintText: l.homeEmptyCreateRubricHint,
          cardTitleText: l.homeEmptyCreateRubric,
          onTap: () => context.push(Routes.buildRubric('new')),
          trailing: const _Chevron(),
        ),
        const SizedBox(height: Insets.lg),
        Center(
          child: TextButton.icon(
            onPressed: loadingSample ? null : onLoadSample,
            icon: loadingSample
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                : const FaIcon(FontAwesomeIcons.wandMagicSparkles, size: 16),
            label: Text(l.homeEmptySampleData),
          ),
        ),
      ],
    );
  }
}
