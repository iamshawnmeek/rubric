# Design decisions

Why the v2 code is shaped the way it is. Each entry says what we saw, what we decided,
and which obvious alternative we rejected. Don't delete an entry when a decision is
reversed: mark it retracted and link the one that replaced it.

## D1: Every grade is computed in `domain/scoring.dart`, and nowhere else

Widgets, exports and the gradebook all need a student's percentage. If each one
re-derived it, a change to penalty or partial-credit rules would ship in one place and
not the others, and a teacher would see two different grades for the same paper.
`Scoring.score(rubric, evaluation)` is the only source. The rules:

- An objective's percent is the raw percent (Simple mode), or the level's points divided
  by the rubric's top level's points (Detailed mode).
- A group's percent is the mean of its **scored** objectives.
- The overall grade is the weight-averaged mean of the groups that have **any** score.
  This keeps a half-graded paper's running grade meaningful. The rejected alternative,
  counting unscored groups as 0, made every paper read as failing until it was
  finished.
- **Missing** with no scores counts as 0. **Excused** never has a grade, even if it has
  scores or an override.
- The penalty is subtracted in percentage points and clamped to 0 or above. An override
  replaces the computed grade, and `rawPercent` keeps the computed value.

## D2: An assignment grades against a snapshot of its rubric

Editing a library rubric must not silently re-grade work that's already marked. So
`Assignment.rubric` is a full copy, taken when the assignment is created.
"Update rubric from library" re-snapshots explicitly, keeping scores for objectives that
still exist. The rejected alternative was a foreign key to the library rubric. It's
simpler, but it rewrites history.

## D3: Weights are whole numbers that always total 100

v1 used a doubly-linked list of "sliders" with fractional weights and let the total
drift. Teachers think in whole percents, and a total of 99.99 is a support ticket
waiting to happen. `domain/weights.dart` keeps the v1 interaction, where dragging a
boundary moves weight between the nearest *unlocked* neighbours. The total is exactly
100 after every operation, and the unit tests enforce it.

## D4: Rubric structure and evaluation scores are stored as JSON documents

They're always read and written whole, and the domain layer owns their shape.
Normalising them into tables would add joins and migrations without enabling a single
query we need. Everything that's filtered or sorted on (titles, course ids, status,
dates) is a real column.

## D5: A persisted rubric never has ungrouped objectives

The domain has no "ungrouped" slot. The builder's tray of not-yet-grouped objectives
lives only in the draft notifier's memory, and the builder won't persist while the tray
is non-empty. First-run onboarding saves the teacher's first objective inside "Group 1"
at weight 100. This contract was agreed between the home and builder Crawlers on
2026-09-29.

## D6: Each checkout runs its own copy of the SDK

Another project's long-lived `flutter run` held the startup lock of the shared fvm SDK
(`~/fvm/versions/3.47.5/bin/cache/lockfile`) and blocked every Flutter command here for
minutes. `tool/flutter` gives each checkout and worktree an APFS copy-on-write clone in
`.sdk/flutter`. It clones in about 5 seconds and uses almost no disk. We rejected
killing the other process, because it belongs to another agent.

## D7: Strings merge by key

Parallel feature branches all append to `app_en.arb`, and line-based merges conflict
on every one. `tool/arb_merge.py` is registered as a git merge driver by
`tool/setup.sh`. It takes the union of the keys and fails only when both sides changed
the same key differently.

## D8: The design system is a fixed input

The palette, Avenir typography and component shapes are the designer's. v2 moved them
into `lib/design_system/` value for value. The only additions are derived text sizes
for dense surfaces, a series ramp built from the existing colors, and spacing tokens
measured from the v1 screens. The app icon is the "r" from the designer's wordmark.
No new color exists anywhere in the app.

## D9: Dependencies that were dropped

- `flow_builder` (a 2021 pre-release) was replaced by go_router.
- The git-hosted `onboarding` package is unmaintained, so the pager is built in-house.
- `double_linked_list` became unnecessary after D3.
- `import_sorter` was replaced by the `directives_ordering` lint.
- `equatable` 3.x couldn't resolve alongside the rest, and records plus explicit `==`
  suffice.
