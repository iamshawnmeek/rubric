import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:rubric/app/routes.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/design_system/design_system.dart';
import 'package:rubric/domain/classroom.dart';
import 'package:rubric/features/classes/classes_providers.dart';
import 'package:rubric/features/classes/classes_widgets.dart';
import 'package:rubric/features/classes/roster_parser.dart';
import 'package:rubric/l10n/l10n.dart';

/// Imports students from a CSV: pick a file or paste text, check the column
/// mapping, review every row, import the selected ones.
class RosterImportPage extends ConsumerStatefulWidget {
  const new({required this.courseId, super.key});

  final String courseId;

  @override
  ConsumerState<RosterImportPage> createState() => _RosterImportPageState();
}

class _RosterImportPageState extends ConsumerState<RosterImportPage> {
  final _paste = TextEditingController();

  /// Null until a CSV is loaded; then the review stage shows.
  RosterTable? _table;
  bool _hasHeader = false;
  List<RosterField> _mapping = const [];
  List<Student> _roster = const [];
  Set<int> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  List<List<String>> get _dataRows {
    final rows = _table?.rows ?? const <List<String>>[];
    return _hasHeader ? rows.skip(1).toList() : rows;
  }

  List<RosterCandidate> get _candidates =>
      buildCandidates(_dataRows, _mapping, existing: _roster);

  bool get _hasNameColumn => _mapping.any(
    (f) =>
        f == RosterField.firstName ||
        f == RosterField.lastName ||
        f == RosterField.fullName,
  );

  void _resetSelection() => _selected = {
    for (final c in _candidates)
      if (c.selectedByDefault) c.row,
  };

  List<RosterField> _detect() {
    final rows = _table!.rows;
    if (_hasHeader) {
      final detected = detectColumns(rows.first);
      final named = detected.any(
        (f) =>
            f == RosterField.firstName ||
            f == RosterField.lastName ||
            f == RosterField.fullName,
      );
      return named ? detected : guessColumns(rows.skip(1).toList());
    }
    return guessColumns(rows);
  }

  /// Everyone in the class, archived included; null while still loading.
  List<Student>? _currentRoster() {
    final active = ref.read(studentsProvider(widget.courseId)).value;
    final archived = ref.read(archivedStudentsProvider(widget.courseId)).value;
    return active == null || archived == null ? null : [...active, ...archived];
  }

  void _load(String text) {
    final l10n = context.l10n;
    final table = parseCsv(text);
    if (table.isEmpty) {
      showRubricSnack(context, l10n.classesImportEmpty);
      return;
    }
    setState(() {
      _roster = _currentRoster()!;
      _table = table;
      _hasHeader = looksLikeHeader(table.rows.first);
      _mapping = _detect();
      _resetSelection();
    });
  }

  Future<void> _pickFile() async {
    final l10n = context.l10n;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'tsv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        // Older spreadsheet exports are often Windows-1252 / Latin-1.
        text = latin1.decode(bytes);
      }
      if (!mounted) return;
      _paste.text = text;
      _load(text);
    } on Exception {
      if (mounted) showRubricSnack(context, l10n.classesImportReadError);
    }
  }

  void _setHeader(bool hasHeader) => setState(() {
    _hasHeader = hasHeader;
    _mapping = _detect();
    _resetSelection();
  });

  Future<void> _mapColumn(int column, String title) async {
    final l10n = context.l10n;
    final field = await showActionSheet<RosterField>(
      context,
      title: title,
      actions: [
        for (final f in RosterField.values)
          SheetAction(
            value: f,
            label: _fieldLabel(l10n, f),
            icon: _fieldIcon(f),
          ),
      ],
    );
    if (field == null) return;
    setState(() {
      _mapping = [
        for (var i = 0; i < _mapping.length; i++)
          if (i == column)
            field
          else if (field != RosterField.ignore && _mapping[i] == field)
            RosterField.ignore
          else
            _mapping[i],
      ];
      _resetSelection();
    });
  }

  Future<void> _import(List<RosterCandidate> chosen) async {
    setState(() => _busy = true);
    await ref.read(courseRepositoryProvider).saveStudents([
      for (final c in chosen) c.toStudent(widget.courseId),
    ]);
    if (!mounted) return;
    showRubricSnack(context, context.l10n.classesStudentsAdded(chosen.length));
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.course(widget.courseId));
    }
  }

  void _startOver() => setState(() {
    _table = null;
    _selected = {};
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final table = _table;
    if (table == null) return _buildSource(context);

    final candidates = _candidates;
    final chosen = [
      for (final c in candidates)
        if (c.importable && _selected.contains(c.row)) c,
    ];
    final importable = candidates.where((c) => c.importable).length;

    return ContentWidth(
      child: RubricPage(
        title: l10n.classesImportTitle,
        showBack: true,
        onBack: _startOver,
        bottomCta: AccentButton(
          label: l10n.classesImportButton(chosen.length),
          onTap: chosen.isEmpty || !_hasNameColumn || _busy
              ? null
              : () => _import(chosen),
          widthFactor: .18,
        ),
        children: [
          _HeaderSwitch(
            label: l10n.classesImportHasHeader,
            value: _hasHeader,
            onChanged: _setHeader,
          ),
          SectionLabel(l10n.classesImportColumnsSection),
          for (var c = 0; c < table.columnCount; c++)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _ColumnMapping(
                title: _hasHeader && table.rows.first[c].isNotEmpty
                    ? table.rows.first[c]
                    : l10n.classesImportColumn(c + 1),
                sample: _dataRows
                    .map((r) => r[c])
                    .firstWhere((v) => v.isNotEmpty, orElse: () => ''),
                field: _mapping[c],
                onTap: (title) => _mapColumn(c, title),
              ),
            ),
          if (!_hasNameColumn)
            _Warning(l10n.classesImportNeedName)
          else ...[
            SectionLabel(
              l10n.classesImportRowsSection,
              trailing: chosen.length < importable
                  ? TextButton(
                      onPressed: () => setState(
                        () => _selected = {
                          for (final c in candidates)
                            if (c.importable) c.row,
                        },
                      ),
                      child: Text(l10n.classesImportSelectAll),
                    )
                  : null,
            ),
            Text(
              l10n.classesImportSelectedSummary(
                chosen.length,
                candidates.length,
              ),
              style: RubricTextStyles.bodySmall,
            ),
            const SizedBox(height: Insets.sm),
            for (final c in candidates)
              _CandidateRow(
                candidate: c,
                selected: c.importable && _selected.contains(c.row),
                onChanged: (on) => setState(() {
                  on ? _selected.add(c.row) : _selected.remove(c.row);
                }),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSource(BuildContext context) {
    final l10n = context.l10n;
    // Watched so the roster is loaded before Preview checks for duplicates.
    final rosterReady =
        ref.watch(studentsProvider(widget.courseId)).hasValue &&
        ref.watch(archivedStudentsProvider(widget.courseId)).hasValue;
    return ContentWidth(
      child: RubricPage(
        title: l10n.classesImportTitle,
        bottomCta: ListenableBuilder(
          listenable: _paste,
          builder: (context, _) => AccentButton(
            label: l10n.classesImportPreview,
            onTap: _paste.text.trim().isEmpty || !rosterReady
                ? null
                : () => _load(_paste.text),
          ),
        ),
        children: [
          Text(l10n.classesImportIntro, style: RubricTextStyles.bodySmall),
          const SizedBox(height: Insets.lg),
          DashedBox(
            label: l10n.classesImportChooseFile,
            onTap: rosterReady ? _pickFile : null,
          ),
          SectionLabel(l10n.classesImportOrPaste),
          RubricFormWell(
            minHeight: 200,
            child: RubricTextField(
              controller: _paste,
              hintText: l10n.classesImportPasteHint,
              semanticLabel: l10n.classesImportOrPaste,
              maxLines: 12,
              minLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.none,
              style: RubricTextStyles.bodySmall.copyWith(color: white),
              hintStyle: RubricTextStyles.bodySmall.copyWith(color: inactive),
            ),
          ),
        ],
      ),
    );
  }
}

String _fieldLabel(AppLocalizations l10n, RosterField f) => switch (f) {
  RosterField.ignore => l10n.classesImportFieldIgnore,
  RosterField.firstName => l10n.classesFirstName,
  RosterField.lastName => l10n.classesLastName,
  RosterField.fullName => l10n.classesImportFieldFullName,
  RosterField.studentNumber => l10n.classesStudentNumber,
  RosterField.email => l10n.classesEmail,
};

FaIconData _fieldIcon(RosterField f) => switch (f) {
  RosterField.ignore => FontAwesomeIcons.ban,
  RosterField.firstName ||
  RosterField.lastName ||
  RosterField.fullName => FontAwesomeIcons.user,
  RosterField.studentNumber => FontAwesomeIcons.hashtag,
  RosterField.email => FontAwesomeIcons.at,
};

class _HeaderSwitch extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: RubricTextStyles.bodySmall.copyWith(color: white),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: secondary,
            activeTrackColor: accent,
          ),
        ],
      ),
    );
  }
}

class _ColumnMapping extends StatelessWidget {
  const new({
    required this.title,
    required this.sample,
    required this.field,
    required this.onTap,
  });

  final String title;
  final String sample;
  final RosterField field;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = _fieldLabel(l10n, field);
    return Semantics(
      button: true,
      label: '$title, ${l10n.classesImportColumnHolds} $label',
      excludeSemantics: true,
      child: Material(
        color: primaryDark,
        borderRadius: Corners.card,
        child: InkWell(
          borderRadius: Corners.card,
          onTap: () => onTap(title),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardHint(
                        title,
                        fontSize: 16,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sample.isNotEmpty)
                        Text(
                          l10n.classesImportColumnSample(sample),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RubricTextStyles.caption.copyWith(
                            color: primaryLighter,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                RubricChip(
                  label: label,
                  selected: field != RosterField.ignore,
                  icon: Icons.expand_more,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.md),
      child: Row(
        children: [
          const FaIcon(
            FontAwesomeIcons.circleExclamation,
            color: accent,
            size: 16,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              text,
              style: RubricTextStyles.bodySmall.copyWith(color: white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const new({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final RosterCandidate candidate;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = candidate;
    final meta = [
      if (c.studentNumber.isNotEmpty)
        l10n.classesStudentNumberTag(c.studentNumber),
      if (c.email.isNotEmpty) c.email,
    ].join(' · ');
    final issue = switch (c.issues) {
      final i when i.contains(RosterIssue.missingName) =>
        l10n.classesImportIssueMissingName,
      final i when i.contains(RosterIssue.alreadyOnRoster) =>
        l10n.classesImportIssueOnRoster,
      final i when i.contains(RosterIssue.duplicateInFile) =>
        l10n.classesImportIssueDuplicate,
      _ => null,
    };
    final toggle = c.importable ? () => onChanged(!selected) : null;

    return MergeSemantics(
      child: InkWell(
        key: ValueKey('candidate-${c.row}'),
        borderRadius: Corners.card,
        onTap: toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: c.importable ? (v) => onChanged(v ?? false) : null,
                activeColor: accent,
                checkColor: secondary,
                side: const BorderSide(color: primaryLight, width: 2),
              ),
              const SizedBox(width: Insets.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName.isEmpty ? '—' : c.displayName,
                        style: RubricTextStyles.listTitle.copyWith(
                          fontSize: 18,
                          color: c.importable ? white : inactive,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(meta, style: RubricTextStyles.caption),
                      if (issue != null)
                        Row(
                          children: [
                            const FaIcon(
                              FontAwesomeIcons.circleExclamation,
                              color: accent,
                              size: 12,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                issue,
                                style: RubricTextStyles.caption.copyWith(
                                  color: primaryLighter,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
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
