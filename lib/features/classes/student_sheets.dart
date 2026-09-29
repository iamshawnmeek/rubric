import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/classes_widgets.dart';
import 'package:rubric/features/classes/roster_parser.dart';
import 'package:rubric/l10n/l10n.dart';

/// Opens the Add/Edit Student sheet against the course's whole roster
/// ([roster], archived included, for duplicate warnings) and saves the
/// result.
Future<Student?> showStudentSheet(
  BuildContext context,
  WidgetRef ref, {
  required String courseId,
  required List<Student> roster,
  Student? student,
}) async {
  final result = await showRubricSheet<Student>(
    context: context,
    child: _StudentForm(courseId: courseId, roster: roster, student: student),
  );
  if (result == null) return null;
  await ref.read(courseRepositoryProvider).saveStudent(result);
  if (context.mounted) {
    showRubricSnack(
      context,
      student == null
          ? context.l10n.classesStudentAdded(result.displayName)
          : context.l10n.classesStudentSaved(result.displayName),
    );
  }
  return result;
}

class _StudentForm extends StatefulWidget {
  const new({required this.courseId, required this.roster, this.student});

  final String courseId;
  final List<Student> roster;
  final Student? student;

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  late final _first = TextEditingController(text: widget.student?.firstName);
  late final _last = TextEditingController(text: widget.student?.lastName);
  late final _number = TextEditingController(
    text: widget.student?.studentNumber,
  );
  late final _email = TextEditingController(text: widget.student?.email);
  late final _matcher = RosterMatcher(
    widget.roster.where((s) => s.id != widget.student?.id),
  );

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _number.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid => _first.text.trim().isNotEmpty;

  bool get _duplicate =>
      _valid &&
      _matcher.matches(_first.text.trim(), _last.text.trim(), _number.text);

  void _submit() {
    if (!_valid) return;
    final first = _first.text.trim();
    final last = _last.text.trim();
    final number = _number.text.trim();
    final email = _email.text.trim();
    final existing = widget.student;
    Navigator.of(context).pop(
      existing == null
          ? Student.create(
              courseId: widget.courseId,
              firstName: first,
              lastName: last,
              studentNumber: number,
              email: email,
            )
          : existing.copyWith(
              firstName: first,
              lastName: last,
              studentNumber: number,
              email: email,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void refresh(String _) => setState(() {});
    return RubricSheet(
      title: widget.student == null
          ? l10n.classesAddStudent
          : l10n.classesEditStudent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RubricFormWell(
            child: Column(
              children: [
                LabeledField(
                  label: l10n.classesFirstName,
                  hint: l10n.classesFirstNameHint,
                  controller: _first,
                  autofocus: widget.student == null,
                  onChanged: refresh,
                ),
                LabeledField(
                  label: l10n.classesLastName,
                  hint: l10n.classesOptional,
                  controller: _last,
                  onChanged: refresh,
                ),
                LabeledField(
                  label: l10n.classesStudentNumber,
                  hint: l10n.classesOptional,
                  controller: _number,
                  textCapitalization: TextCapitalization.none,
                  onChanged: refresh,
                ),
                LabeledField(
                  label: l10n.classesEmail,
                  hint: l10n.classesOptional,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
          if (_duplicate) ...[
            const SizedBox(height: Insets.sm),
            _Notice(l10n.classesStudentDuplicate),
          ],
          const SizedBox(height: Insets.lg),
          AccentButton(
            label: widget.student == null
                ? l10n.classesAddStudent
                : l10n.classesSave,
            onTap: _valid ? _submit : null,
            widthFactor: .15,
          ),
        ],
      ),
    );
  }
}

/// A warning line: an icon plus words, so it never relies on color alone.
class _Notice extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: FaIcon(
            FontAwesomeIcons.circleExclamation,
            color: accent,
            size: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: RubricTextStyles.caption.copyWith(color: primaryLighter),
          ),
        ),
      ],
    );
  }
}

/// The bulk "paste names" quick add. Adds every new name; names already in
/// [roster] (or repeated in the paste) are skipped. Resolves to the count
/// added.
Future<int> showPasteNamesSheet(
  BuildContext context,
  WidgetRef ref, {
  required String courseId,
  required List<Student> roster,
}) async {
  final added = await showRubricSheet<List<Student>>(
    context: context,
    child: _PasteNames(courseId: courseId, roster: roster),
  );
  if (added == null || added.isEmpty) return 0;
  await ref.read(courseRepositoryProvider).saveStudents(added);
  if (context.mounted) {
    showRubricSnack(context, context.l10n.classesStudentsAdded(added.length));
  }
  return added.length;
}

class _PasteNames extends StatefulWidget {
  const new({required this.courseId, required this.roster});

  final String courseId;
  final List<Student> roster;

  @override
  State<_PasteNames> createState() => _PasteNamesState();
}

class _PasteNamesState extends State<_PasteNames> {
  final _text = TextEditingController();
  List<RosterCandidate> _candidates = const [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse(String text) => setState(
    () => _candidates = candidatesFromNames(
      parseNameLines(text),
      existing: widget.roster,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toAdd = _candidates.where((c) => c.issues.isEmpty).toList();
    final skipped = _candidates.length - toAdd.length;

    return RubricSheet(
      title: l10n.classesPasteNames,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RubricFormWell(
            minHeight: 180,
            child: RubricTextField(
              controller: _text,
              hintText: l10n.classesPasteHint,
              semanticLabel: l10n.classesPasteNames,
              autofocus: true,
              maxLines: 10,
              minLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.words,
              onChanged: _parse,
              style: RubricTextStyles.bodyPlaceholder.copyWith(fontSize: 20),
              hintStyle: RubricTextStyles.bodyPlaceholder.copyWith(
                fontSize: 20,
                color: inactive,
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            l10n.classesPasteSummary(toAdd.length),
            style: RubricTextStyles.bodySmall.copyWith(color: white),
          ),
          if (skipped > 0) ...[
            const SizedBox(height: 4),
            _Notice(l10n.classesPasteSkipped(skipped)),
          ],
          const SizedBox(height: Insets.lg),
          AccentButton(
            label: l10n.classesPasteAdd(toAdd.length),
            onTap: toAdd.isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop([for (final c in toAdd) c.toStudent(widget.courseId)]),
            widthFactor: .15,
          ),
        ],
      ),
    );
  }
}

enum StudentAction { edit, archive, restore, remove }

/// Edit / archive / restore / remove for one student.
Future<void> showStudentActions(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
  required List<Student> roster,
}) async {
  final l10n = context.l10n;
  final action = await showActionSheet<StudentAction>(
    context,
    title: student.displayName,
    actions: [
      SheetAction(
        value: StudentAction.edit,
        label: l10n.classesEdit,
        icon: FontAwesomeIcons.pen,
      ),
      if (student.archived)
        SheetAction(
          value: StudentAction.restore,
          label: l10n.classesRestore,
          icon: FontAwesomeIcons.boxOpen,
        )
      else
        SheetAction(
          value: StudentAction.archive,
          label: l10n.classesArchive,
          icon: FontAwesomeIcons.boxArchive,
        ),
      SheetAction(
        value: StudentAction.remove,
        label: l10n.classesStudentRemove,
        icon: FontAwesomeIcons.userMinus,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  final repo = ref.read(courseRepositoryProvider);
  switch (action) {
    case StudentAction.edit:
      await showStudentSheet(
        context,
        ref,
        courseId: student.courseId,
        roster: roster,
        student: student,
      );
    case StudentAction.archive:
    case StudentAction.restore:
      await repo.saveStudent(student.copyWith(archived: !student.archived));
      if (!context.mounted) return;
      showRubricSnack(
        context,
        student.archived
            ? l10n.classesStudentRestoredSnack(student.displayName)
            : l10n.classesStudentArchivedSnack(student.displayName),
        action: SnackBarAction(
          label: l10n.classesUndo,
          onPressed: () => repo.saveStudent(student),
        ),
      );
    case StudentAction.remove:
      final ok = await confirm(
        context,
        title: l10n.classesStudentRemoveTitle(student.displayName),
        message: l10n.classesStudentRemoveMessage,
        confirmLabel: l10n.classesStudentRemoveConfirm,
      );
      if (!ok) return;
      await repo.deleteStudent(student.id);
      if (context.mounted) {
        showRubricSnack(
          context,
          l10n.classesStudentRemovedSnack(student.displayName),
        );
      }
  }
}
