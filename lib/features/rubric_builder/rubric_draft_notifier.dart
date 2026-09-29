import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show AsyncNotifierProviderFamily;
import 'package:rubric/app/settings.dart';
import 'package:rubric/data/providers.dart';
import 'package:rubric/domain/grading_scale.dart';
import 'package:rubric/domain/ids.dart';
import 'package:rubric/domain/rubric.dart';
import 'package:rubric/domain/weights.dart';
import 'package:rubric/features/rubric_builder/rubric_draft.dart';

/// The rubric id the builder route uses for "start a fresh rubric".
const newRubricId = 'new';

/// The rubric under edit, keyed by the route's rubric id. Resolves to null
/// when an existing rubric cannot be found (deleted on another screen).
final AsyncNotifierProviderFamily<RubricDraftNotifier, RubricDraft?, String>
rubricDraftProvider = AsyncNotifierProvider.autoDispose
    .family<RubricDraftNotifier, RubricDraft?, String>(RubricDraftNotifier.new);

class RubricDraftNotifier extends AsyncNotifier<RubricDraft?> {
  new(this.rubricId);

  final String rubricId;

  @override
  FutureOr<RubricDraft?> build() async {
    if (rubricId == newRubricId) {
      final settings = ref.read(settingsProvider);
      final rubric = Rubric.create().copyWith(
        mode: settings.defaultMode,
        scale: settings.defaultScale,
      );
      return RubricDraft(rubric: rubric, baseline: rubric, isNew: true);
    }
    final rubric = await ref.read(rubricRepositoryProvider).get(rubricId);
    if (rubric == null) return null;
    return RubricDraft(rubric: rubric, baseline: rubric, isNew: false);
  }

  RubricDraft get _draft => state.requireValue!;

  void _set(RubricDraft draft) => state = AsyncData(draft);

  void _editRubric(Rubric Function(Rubric rubric) change) =>
      _set(_draft.copyWith(rubric: change(_draft.rubric)));

  // ---- Objectives ----------------------------------------------------------

  /// Adds a new objective to the ungrouped tray. Blank titles are ignored.
  Objective? addObjective(String title, {String description = ''}) {
    if (title.trim().isEmpty) return null;
    final objective = Objective.create(title.trim())
        .copyWith(description: description.trim());
    _set(_draft.copyWith(ungrouped: [..._draft.ungrouped, objective]));
    return objective;
  }

  void updateObjective(String id, {String? title, String? description}) {
    if (title != null && title.trim().isEmpty) return;
    _mapObjectives(
      (o) => o.id != id
          ? o
          : o.copyWith(title: title?.trim(), description: description?.trim()),
    );
  }

  /// Deletes the objective, dropping its group if that leaves it empty.
  /// Returns what [restoreObjective] needs to undo it.
  RemovedObjective? removeObjective(String id) {
    final draft = _draft;
    final groups = draft.rubric.groups;
    for (var gi = 0; gi < groups.length; gi++) {
      final index = groups[gi].objectives.indexWhere((o) => o.id == id);
      if (index < 0) continue;
      final group = groups[gi];
      _setGroups([
        for (final g in groups)
          if (g.id == group.id)
            g.copyWith(objectives: [...g.objectives]..removeAt(index))
          else
            g,
      ]);
      return RemovedObjective(
        objective: group.objectives[index],
        index: index,
        group: group,
        groupIndex: gi,
      );
    }
    final index = draft.ungrouped.indexWhere((o) => o.id == id);
    if (index < 0) return null;
    _set(draft.copyWith(ungrouped: [...draft.ungrouped]..removeAt(index)));
    return RemovedObjective(objective: draft.ungrouped[index], index: index);
  }

  /// Puts a removed objective back where it was, recreating its group (with
  /// its old title and weight) when the removal had dropped it.
  void restoreObjective(RemovedObjective removed) {
    // Undo arrives from a snackbar that can outlive the builder.
    if (!ref.mounted) return;
    final draft = _draft;
    final group = removed.group;
    if (group == null) {
      final tray = [...draft.ungrouped];
      tray.insert(removed.index.clamp(0, tray.length), removed.objective);
      _set(draft.copyWith(ungrouped: tray));
      return;
    }
    final groups = [...draft.rubric.groups];
    final existing = groups.indexWhere((g) => g.id == group.id);
    if (existing >= 0) {
      final objectives = [...groups[existing].objectives];
      objectives.insert(
        removed.index.clamp(0, objectives.length),
        removed.objective,
      );
      groups[existing] = groups[existing].copyWith(objectives: objectives);
    } else {
      // Give the group back its old weight, shrinking the others to fit.
      final others = groups.fold(0, (sum, g) => sum + g.weight);
      final weights = fitWeights(
        [
          for (final g in groups)
            if (others == 0) 1 else g.weight * (100 - group.weight) / others,
        ]..insert(
          (removed.groupIndex ?? groups.length).clamp(0, groups.length),
          group.weight,
        ),
      );
      groups.insert(
        (removed.groupIndex ?? groups.length).clamp(0, groups.length),
        group.copyWith(objectives: [removed.objective]),
      );
      for (var i = 0; i < groups.length; i++) {
        groups[i] = groups[i].copyWith(weight: weights[i]);
      }
    }
    _setGroups(groups);
  }

  /// Moves the objective at flat position [from] (see
  /// [RubricDraft.objectives]) to [to], counted after the removal. An
  /// objective stays inside its own group here; moving between groups is the
  /// groups step's job.
  void reorderObjective(int from, int to) {
    final draft = _draft;
    var start = 0;
    for (final group in draft.rubric.groups) {
      final end = start + group.objectives.length;
      if (from < end) {
        final objectives = _reordered(
          group.objectives,
          from - start,
          to - start,
        );
        _editRubric(
          (r) => r.copyWith(
            groups: [
              for (final g in r.groups)
                if (g.id == group.id) g.copyWith(objectives: objectives) else g,
            ],
          ),
        );
        return;
      }
      start = end;
    }
    if (from - start >= draft.ungrouped.length) return;
    _set(
      draft.copyWith(
        ungrouped: _reordered(draft.ungrouped, from - start, to - start),
      ),
    );
  }

  static List<Objective> _reordered(List<Objective> list, int from, int to) {
    final next = [...list];
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
    return next;
  }

  // ---- Groups --------------------------------------------------------------

  /// Moves the objective into the group [groupId], or back to the ungrouped
  /// tray when [groupId] is null. Groups left empty are removed.
  void moveObjective(String objectiveId, {String? groupId}) {
    final draft = _draft;
    final objective = draft.objectives.firstWhereOrNull(
      (o) => o.id == objectiveId,
    );
    if (objective == null) return;
    if (groupId == null
        ? draft.ungrouped.contains(objective)
        : draft.rubric.groupOf(objectiveId)?.id == groupId ||
              draft.rubric.groups.every((g) => g.id != groupId)) {
      return;
    }
    final tray = [
      for (final o in draft.ungrouped)
        if (o.id != objectiveId) o,
      if (groupId == null) objective,
    ];
    _set(draft.copyWith(ungrouped: tray));
    _setGroups([
      for (final g in draft.rubric.groups)
        g.copyWith(
          objectives: [
            for (final o in g.objectives)
              if (o.id != objectiveId) o,
            if (g.id == groupId) objective,
          ],
        ),
    ]);
  }

  /// Starts a new group called [title] holding just this objective.
  void moveToNewGroup(String objectiveId, {required String title}) {
    final draft = _draft;
    final objective = draft.objectives.firstWhereOrNull(
      (o) => o.id == objectiveId,
    );
    if (objective == null) return;
    _set(
      draft.copyWith(
        ungrouped: [
          for (final o in draft.ungrouped)
            if (o.id != objectiveId) o,
        ],
      ),
    );
    _setGroups([
      for (final g in draft.rubric.groups)
        g.copyWith(
          objectives: [
            for (final o in g.objectives)
              if (o.id != objectiveId) o,
          ],
        ),
      RubricGroup.create(title).copyWith(objectives: [objective]),
    ]);
  }

  /// The one-tap shortcut: every objective, in order, in a single group. The
  /// first existing group is kept (with its title); otherwise one called
  /// [title] is created.
  void groupEverything({required String title}) {
    final draft = _draft;
    final all = draft.objectives;
    if (all.isEmpty) return;
    final keep = draft.rubric.groups.firstOrNull ?? RubricGroup.create(title);
    _set(draft.copyWith(ungrouped: const []));
    _setGroups([keep.copyWith(objectives: all, weight: 100)]);
  }

  void renameGroup(String groupId, String title) => _editRubric(
    (r) => r.copyWith(
      groups: [
        for (final g in r.groups)
          if (g.id == groupId) g.copyWith(title: title) else g,
      ],
    ),
  );

  /// Dissolves the group; its objectives go back to the tray.
  void removeGroup(String groupId) {
    final draft = _draft;
    final group = draft.rubric.groups.firstWhereOrNull((g) => g.id == groupId);
    if (group == null) return;
    _set(draft.copyWith(ungrouped: [...draft.ungrouped, ...group.objectives]));
    _setGroups([
      for (final g in draft.rubric.groups)
        if (g.id != groupId) g,
    ]);
  }

  /// Replaces the groups, dropping empty ones. When the set of groups changed,
  /// weights are refitted to 100 keeping the surviving groups' proportions
  /// (a new group with no weight yet gets an even share) and locks are
  /// cleared, since the positions they referred to have moved.
  void _setGroups(List<RubricGroup> next) {
    final draft = _draft;
    final kept = [
      for (final g in next)
        if (g.objectives.isNotEmpty) g,
    ];
    final before = {for (final g in draft.rubric.groups) g.id};
    final after = {for (final g in kept) g.id};
    if (const SetEquality<String>().equals(before, after)) {
      _set(draft.copyWith(rubric: draft.rubric.copyWith(groups: kept)));
      return;
    }
    // A new group weighs as much as the average surviving one, so adding a
    // third to 50/50 gives thirds rather than squeezing the newcomer.
    final old = [
      for (final g in kept)
        if (before.contains(g.id)) g.weight,
    ];
    final share = old.isEmpty ? 100 : old.sum / old.length;
    final weights = fitWeights([
      for (final g in kept)
        if (before.contains(g.id) || g.weight > 0) g.weight else share,
    ]);
    _set(
      draft.copyWith(
        rubric: draft.rubric.copyWith(
          groups: [
            for (var i = 0; i < kept.length; i++)
              kept[i].copyWith(weight: weights[i]),
          ],
        ),
        locked: const {},
      ),
    );
  }

  // ---- Weights -------------------------------------------------------------

  Set<int> get _lockedIndexes => {
    for (var i = 0; i < _draft.rubric.groups.length; i++)
      if (_draft.locked.contains(_draft.rubric.groups[i].id)) i,
  };

  List<int> get _weights => [for (final g in _draft.rubric.groups) g.weight];

  void _applyWeights(List<int> weights) => _editRubric(
    (r) => r.copyWith(
      groups: [
        for (var i = 0; i < r.groups.length; i++)
          r.groups[i].copyWith(weight: weights[i]),
      ],
    ),
  );

  void toggleLock(String groupId) {
    final locked = {..._draft.locked};
    if (!locked.remove(groupId)) locked.add(groupId);
    _set(_draft.copyWith(locked: locked));
  }

  /// Drags the boundary under group [boundary] by [delta] points; positive
  /// grows the group above. See [Weights.moveBoundary].
  void moveBoundary(int boundary, int delta) => _applyWeights(
    Weights.moveBoundary(
      weights: _weights,
      locked: _lockedIndexes,
      boundary: boundary,
      delta: delta,
    ),
  );

  /// Sets one group's exact weight; the unlocked others absorb the change.
  void setWeight(String groupId, int value) {
    final index = _draft.rubric.groups.indexWhere((g) => g.id == groupId);
    if (index < 0) return;
    _applyWeights(
      Weights.setWeight(
        weights: _weights,
        locked: _lockedIndexes,
        index: index,
        value: value,
      ),
    );
  }

  /// Splits 100 evenly across every group and releases all locks.
  void evenSplit() {
    _applyWeights(Weights.equalSplit(_draft.rubric.groups.length));
    _set(_draft.copyWith(locked: const {}));
  }

  // ---- Grading scale -------------------------------------------------------

  void setMode(GradingMode mode) => _editRubric(
    (r) => r.copyWith(
      mode: mode,
      levels: mode == GradingMode.detailed && r.levels.isEmpty
          ? PerformanceLevel.defaults()
          : null,
    ),
  );

  void applyScale(GradingScale scale) =>
      _editRubric((r) => r.copyWith(scale: scale));

  void updateBand(int index, {String? letter, double? min}) {
    final bands = [..._draft.rubric.scale.bands];
    if (index < 0 || index >= bands.length) return;
    final band = bands[index];
    bands[index] = LetterBand(letter ?? band.letter, min ?? band.min);
    applyScale(GradingScale(bands));
  }

  /// Appends an unnamed grade halfway below the lowest non-zero one (or at
  /// 0 when nothing starts at 0 yet).
  void addBand() {
    final bands = _draft.rubric.scale.bands;
    final mins = bands.map((b) => b.min);
    final lowest = mins.where((m) => m > 0).minOrNull;
    final min = !mins.contains(0) || lowest == null
        ? 0.0
        : (lowest / 2).floorToDouble();
    applyScale(GradingScale([...bands, LetterBand('', min)]));
  }

  void removeBand(int index) {
    final bands = [..._draft.rubric.scale.bands];
    if (bands.length <= 1 || index < 0 || index >= bands.length) return;
    applyScale(GradingScale(bands..removeAt(index)));
  }

  // ---- Performance levels (detailed mode) ----------------------------------

  /// Adds a level at the bottom of the ladder, one point under the lowest
  /// (or at the top, one over the highest, when the bottom is already 0).
  void addLevel(String label) {
    final levels = _draft.rubric.levels;
    final lowest = levels.map((l) => l.points).minOrNull;
    final highest = levels.map((l) => l.points).maxOrNull;
    final level = PerformanceLevel(id: newId(), label: label, points: 1);
    _editRubric(
      (r) => r.copyWith(
        levels: lowest == null
            ? [level]
            : lowest >= 1
            ? [...levels, level.copyWith(points: lowest - 1)]
            : [level.copyWith(points: highest! + 1), ...levels],
      ),
    );
  }

  void updateLevel(String levelId, {String? label, double? points}) =>
      _editRubric(
        (r) => r.copyWith(
          levels: [
            for (final l in r.levels)
              if (l.id == levelId)
                l.copyWith(label: label, points: points)
              else
                l,
          ],
        ),
      );

  /// Removes the level and every descriptor written for it.
  void removeLevel(String levelId) {
    _editRubric(
      (r) => r.copyWith(
        levels: [...r.levels]..removeWhere((l) => l.id == levelId),
      ),
    );
    _mapObjectives(
      (o) => o.descriptors.containsKey(levelId)
          ? o.copyWith(descriptors: {...o.descriptors}..remove(levelId))
          : o,
    );
  }

  /// Moves a level up (negative [delta]) or down the ladder.
  void moveLevel(String levelId, int delta) {
    final levels = [..._draft.rubric.levels];
    final from = levels.indexWhere((l) => l.id == levelId);
    if (from < 0) return;
    final to = (from + delta).clamp(0, levels.length - 1);
    if (to == from) return;
    levels.insert(to, levels.removeAt(from));
    _editRubric((r) => r.copyWith(levels: levels));
  }

  /// What [levelId] looks like for [objectiveId]; blank text clears it.
  void setDescriptor(String objectiveId, String levelId, String text) =>
      _mapObjectives((o) {
        if (o.id != objectiveId) return o;
        final descriptors = {...o.descriptors};
        if (text.trim().isEmpty) {
          descriptors.remove(levelId);
        } else {
          descriptors[levelId] = text;
        }
        return o.copyWith(descriptors: descriptors);
      });

  // ---- Details & saving ----------------------------------------------------

  void setDetails({String? title, String? subject, String? description}) =>
      _editRubric(
        (r) => r.copyWith(
          title: title,
          subject: subject,
          description: description,
        ),
      );

  /// Writes the rubric (scale sorted, text trimmed) and makes it the new
  /// baseline. Only call when [RubricDraft.ungrouped] is empty — the library
  /// has nowhere to keep ungrouped objectives.
  Future<Rubric> save() async {
    final draft = _draft;
    assert(draft.ungrouped.isEmpty, 'group every objective before saving');
    final rubric = draft.rubric.copyWith(
      title: draft.rubric.title.trim(),
      subject: draft.rubric.subject.trim(),
      description: draft.rubric.description.trim(),
      scale: draft.sortedScale,
      groups: [
        for (final g in draft.rubric.groups) g.copyWith(title: g.title.trim()),
      ],
    );
    final saved = await ref.read(rubricRepositoryProvider).save(rubric);
    if (ref.mounted) {
      _set(_draft.copyWith(rubric: saved, baseline: saved, isNew: false));
    }
    return saved;
  }

  void _mapObjectives(Objective Function(Objective o) change) {
    final draft = _draft;
    _set(
      draft.copyWith(
        ungrouped: [for (final o in draft.ungrouped) change(o)],
        rubric: draft.rubric.copyWith(
          groups: [
            for (final g in draft.rubric.groups)
              g.copyWith(objectives: [for (final o in g.objectives) change(o)]),
          ],
        ),
      ),
    );
  }
}
