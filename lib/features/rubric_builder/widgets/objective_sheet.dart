import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/l10n/l10n.dart';

/// What the teacher typed into the objective sheet.
typedef ObjectiveInput = ({String title, String description});

/// The v1 "Add an Objective" sheet, also used to edit one. Resolves to null
/// when dismissed.
Future<ObjectiveInput?> showObjectiveSheet(
  BuildContext context, {
  Objective? editing,
}) => showRubricSheet<ObjectiveInput>(
  context: context,
  child: _ObjectiveSheet(editing: editing),
);

class _ObjectiveSheet extends StatefulWidget {
  const new({this.editing});

  final Objective? editing;

  @override
  State<_ObjectiveSheet> createState() => _ObjectiveSheetState();
}

class _ObjectiveSheetState extends State<_ObjectiveSheet> {
  late final _title = TextEditingController(text: widget.editing?.title);
  late final _description = TextEditingController(
    text: widget.editing?.description,
  );

  bool get _canSubmit => _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop<ObjectiveInput>((
      title: _title.text.trim(),
      description: _description.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final editing = widget.editing != null;
    final width = MediaQuery.sizeOf(context).width;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: RubricSheet(
        title: editing ? l.builderEditObjective : l.builderAddObjective,
        // Clip so the FAB can slide in from beyond the sheet's edge, like v1.
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RubricFormWell(
                    minHeight: 180,
                    child: RubricTextField(
                      controller: _title,
                      hintText: l.builderObjectiveTitleHint,
                      semanticLabel: l.builderObjectiveTitleLabel,
                      autofocus: true,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                  RubricFormWell(
                    child: RubricTextField(
                      controller: _description,
                      hintText: l.builderObjectiveDescriptionHint,
                      style: RubricTextStyles.bodySmall,
                      maxLines: 4,
                      minLines: 1,
                    ),
                  ),
                  // Room for the FAB under the fields.
                  const SizedBox(height: 80),
                ],
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: Curves.ease,
                right: _canSubmit ? 0 : -width,
                bottom: 0,
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: editing
                      ? l.builderObjectiveSave
                      : l.builderObjectiveAdd,
                  foregroundColor: primaryDark,
                  backgroundColor: accent,
                  onPressed: _canSubmit ? _submit : null,
                  child: FaIcon(
                    editing ? FontAwesomeIcons.check : FontAwesomeIcons.plus,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
