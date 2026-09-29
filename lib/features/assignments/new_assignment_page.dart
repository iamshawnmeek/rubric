import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/assignment.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/features/assignments/assignment_logic.dart';
import 'package:rubric/features/assignments/assignment_widgets.dart';
import 'package:rubric/features/assignments/rubric_picker_sheet.dart';
import 'package:rubric/l10n/l10n.dart';

/// Create an assignment in a course: details plus a rubric that is
/// snapshotted into it. Seeds a `notStarted` evaluation for every active
/// student and lands on the assignment hub.
class NewAssignmentPage extends ConsumerStatefulWidget {
  const new({required this.courseId, super.key});

  final String courseId;

  @override
  ConsumerState<NewAssignmentPage> createState() => _NewAssignmentPageState();
}

class _NewAssignmentPageState extends ConsumerState<NewAssignmentPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _points = TextEditingController(text: '100');
  DateTime? _dueDate;
  Rubric? _rubric;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _points.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _points.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving &&
      _title.text.trim().isNotEmpty &&
      parsePoints(_points.text) != null &&
      _rubric != null &&
      canAttach(_rubric!);

  Future<void> _chooseRubric() async {
    final picked = await showRubricPicker(context);
    if (picked != null && mounted) setState(() => _rubric = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final assignments = ref.read(assignmentRepositoryProvider);
    final students = await ref
        .read(courseRepositoryProvider)
        .students(widget.courseId);
    final assignment = Assignment.create(
      courseId: widget.courseId,
      title: _title.text.trim(),
      description: _description.text.trim(),
      rubric: snapshotOf(_rubric!),
      dueDate: _dueDate,
      pointsPossible: parsePoints(_points.text)!,
    );
    await assignments.save(assignment);
    await assignments.saveEvaluations(
      missingEvaluations(assignment, students, const []),
    );
    if (!mounted) return;
    context.go(Routes.assignment(widget.courseId, assignment.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final course = ref.watch(courseProvider(widget.courseId));
    final gutter = contentGutter(context);

    return RubricPage(
      title: l10n.assignmentsNewTitle,
      subtitle: course.value?.name,
      showBack: true,
      bottomCta: AccentButton(
        key: const Key('assignments.create'),
        label: l10n.assignmentsCreate,
        widthFactor: .2,
        onTap: _canSave ? _save : null,
      ),
      slivers: [
        SliverPadding(
          padding: gutter,
          sliver: SliverList.list(
            children: [
              if (course case AsyncData(value: null))
                EmptyState(title: l10n.assignmentsCourseMissing)
              else ...[
                AssignmentDetailsFields(
                  title: _title,
                  description: _description,
                  points: _points,
                  dueDate: _dueDate,
                  onDueDateChanged: (d) => setState(() => _dueDate = d),
                  autofocusTitle: true,
                ),
                SectionLabel(l10n.assignmentsRubricLabel),
                if (_rubric case final rubric?)
                  RubricCard(
                    key: const Key('assignments.chosenRubric'),
                    cardHintText: rubricSummary(context, rubric),
                    cardTitleText: rubric.title,
                    onTap: _chooseRubric,
                    trailing: Text(
                      l10n.assignmentsChangeRubric,
                      style: RubricTextStyles.button.copyWith(color: accent),
                    ),
                  )
                else
                  DashedBox(
                    key: const Key('assignments.chooseRubric'),
                    label: l10n.assignmentsChooseRubric,
                    onTap: _chooseRubric,
                  ),
                const SizedBox(height: Insets.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: Insets.xs),
                      child: FaIcon(
                        FontAwesomeIcons.circleInfo,
                        size: 14,
                        color: primaryLight,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.assignmentsSnapshotNote,
                        style: RubricTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
