import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';

/// "Let's create your first rubric." — asks for the first grading objective.
///
/// Resolves to the trimmed objective, or null when dismissed. The orange add
/// button slides in from the right once there is something to add, as in v1.
Future<String?> showFirstObjectiveSheet(BuildContext context) =>
    showRubricSheet<String>(
      context: context,
      child: const FirstObjectiveSheet(),
    );

class FirstObjectiveSheet extends StatefulWidget {
  const new({super.key});

  @override
  State<FirstObjectiveSheet> createState() => _FirstObjectiveSheetState();
}

class _FirstObjectiveSheetState extends State<FirstObjectiveSheet> {
  final _controller = TextEditingController();

  static const _fabSize = 56.0;

  bool get _canContinue => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_canContinue) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RubricSheet(
      title: l.welcomeFirstRubricTitle,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Insets.md),
                RubricFormWell(
                  minHeight: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BodyOne(l.welcomeFirstObjectivePrompt),
                      const SizedBox(height: Insets.xl),
                      RubricTextField(
                        controller: _controller,
                        hintText: l.welcomeFirstObjectiveHint,
                        semanticLabel: l.welcomeFirstObjectivePrompt,
                        maxLines: 2,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
              ],
            ),
            AnimatedPositioned(
              duration: disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 500),
              curve: Curves.ease,
              right: _canContinue ? -5 : -constraints.maxWidth - 40,
              bottom: 0,
              child: ExcludeSemantics(
                excluding: !_canContinue,
                child: Semantics(
                  button: true,
                  label: l.welcomeFirstObjectiveCreate,
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: _fabSize,
                    child: Material(
                      color: accent,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _canContinue ? _submit : null,
                        child: const Center(
                          child: FaIcon(
                            FontAwesomeIcons.plus,
                            color: primaryDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
