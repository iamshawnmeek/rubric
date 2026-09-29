import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/l10n/l10n.dart';

/// What to do with a generated PDF.
enum PdfDestination { print, share }

/// The small sheet offered before every PDF export. Resolves null when the
/// sheet is dismissed.
Future<PdfDestination?> showPdfDestinationSheet(
  BuildContext context, {
  required String documentName,
}) => showRubricSheet<PdfDestination>(
  context: context,
  child: PdfDestinationSheet(documentName: documentName),
);

class PdfDestinationSheet extends StatelessWidget {
  const new({required this.documentName, super.key});

  final String documentName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget option(
      PdfDestination d,
      String hint,
      String title,
      FaIconData icon,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: RubricCard(
        key: ValueKey(d),
        cardHintText: hint,
        cardTitleText: title,
        color: primary,
        onTap: () => Navigator.of(context).pop(d),
        trailing: FaIcon(icon, color: accent, size: 22),
      ),
    );

    return RubricSheet(
      title: l10n.exportSheetTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            documentName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: RubricTextStyles.bodySmall,
          ),
          const SizedBox(height: Insets.lg),
          option(
            PdfDestination.print,
            l10n.exportSheetPrintHint,
            l10n.exportSheetPrint,
            FontAwesomeIcons.print,
          ),
          option(
            PdfDestination.share,
            l10n.exportSheetShareHint,
            l10n.exportSheetShare,
            FontAwesomeIcons.shareFromSquare,
          ),
        ],
      ),
    );
  }
}
