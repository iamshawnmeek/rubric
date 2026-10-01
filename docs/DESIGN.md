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

## D10: The backend is Firebase + firefuel, synced from drift, behind a backend-neutral interface (2026-09-29): RETRACTED, see D11

We researched both options in depth. That covered the zonai v0.9.4 source and docs,
the Firebase docs and the firefuel repo, and how zonai is actually used in
gravity_brew, wholesale-command-station and llm_chat.

**Common ground.** Neither backend does offline sync the way Rubric needs it:

- zonai has no offline support at all.
- Firestore's cache is not an offline-first database. It has no local indexes, a
  transaction fails while offline, and a listener that reconnects after 30 minutes
  or more is billed as a new query.

So drift stays the source of truth, and Rubric owns a sync engine behind a
`SyncBackend` interface: an outbox, pushes, and cursor-based pulls with tombstones
for deletes. gravity_brew's engine is the proven pattern to follow. Schema v2 adds
`updatedAt`, `deletedAt` and a revision to every table. Evaluations get a
deterministic id, `{assignmentId}_{studentId}`, because neither backend enforces
our unique key across devices.

**Why Firebase first.** Rubric stores minors' grades. On zonai v0.9.4 we verified
these gaps:

- The count endpoints skip row rules, so any teacher can count other teachers'
  rows under any filter.
- No query is scoped by the caller's JWT on the server.
- The unique index on auth email is never created.
- Owners can edit their own `is_verified`.
- There is no encryption at rest, no backups, and no way to delete an account.
- Rate limits are keyed by IP, so a whole school behind one NAT shares one budget.
- zonai_client streams swallow errors and never reconnect.
- The project is five months old with a single maintainer.

Firebase gives us, today: encryption at rest, daily and weekly backups plus 7-day
point-in-time recovery, SOC and ISO attestations, mature SDKs, rules we can test
in the emulator, and Google sign-in, which fits schools that use Google
Classroom. At 50k teachers, drift-plus-sync reads cost about $2.5k/month.
firefuel 0.5.0 resolves against our exact toolchain.

**Why zonai stays in the plan.** Firebase Auth runs only in US data centers, so a
district that requires in-country identity data can't use it. zonai self-hosted per
district is the answer for that case, and it maps onto our schema almost
one-to-one. The `SyncBackend` seam keeps that door open: adding zonai later means
writing one adapter, not rewriting the app. We have write access to zonai, and
the contributions it needs (a JWT-scoped query filter that closes the count leak,
a server sequence column, per-user rate limits, the auth fixes, backup,
encryption at rest) are costed in the research notes. The security fixes are
worth making anyway, because other projects on this machine run on the same
version.

**Rejected:**
- Replacing drift with Firestore's cache: poor offline query performance, it
  loses our relational guarantees, and it costs more per read.
- zonai-only now: student data would sit behind the verified authorization gaps
  above until they're fixed.
- Running both backends in production from day one: twice the operational load
  before we have a single user.

## D11: The backend is zonai, with sync built into zonai as a standard capability (2026-09-29)

This supersedes D10. D10 put Firebase first because zonai v0.9.4 had verified
authorization and privacy gaps and no sync support. The human chose to fix that at
the source instead: "get zonai working the way we want it to". We have write access
to zonai, and it now has its own owner agent. Every gap D10 listed becomes one of two
things:

- a core fix or feature, owned by zonai-owner: scoped queries that close the count
  leak, sequence and revision columns, update preconditions, a changes feed, batch
  writes, per-user rate limits, and the auth fixes;
- a standard sync package set, `zonai_sync_schema`, `zonai_sync` and
  `zonai_sync_gen` (see `docs/zonai_sync/DESIGN.md`).

gravity_brew and future zonai apps benefit as well. What D10 got right still holds:
drift stays the source of truth, and ordering never compares client and server
clocks. Firebase stays documented in D10 as the fallback if zonai's gaps can't be
closed.

**How Rubric uses it (2026-09-29):**
- Every repository write goes through `SyncService`, Rubric's `SyncWriter`. It
  writes locally while signed out, and through `zonai_sync`'s engine while
  signed in. `lib/sync/sync_tables.dart` maps drift rows to the server's wire
  format, one adapter per table.
- Children declare `references`, so a stuck parent row holds only its own
  children. Deletes cascade explicitly as tombstones, children first.
  Evaluation ids are deterministic per (assignment, student), so two devices
  grading the same paper converge on one row.
- Bulk changes that write drift directly (sample data, backup restore and its
  undo) run inside `SyncService.bulk`, which diffs a snapshot. Without it,
  directly deleted rows would stay alive on the server.
- Signing out removes the account's data from the device. Erase-all signs out
  first, so erasing one device never tombstones the account.
- Verified by `tool/sync_e2e.sh`: an iOS simulator and an Android emulator on
  one account, against a local zonai 0.9.4.

**On the next zonai release (2026-09-30). Done 2026-09-30 on v0.10.0: steps 1, 2 and 4. Step 3 ($.revision) is deferred; see below.** Everything Rubric needs is on zonai main: #44, #48, #49, #62, #56, #45, plus #51 and #60 for later. Morgan cuts the release. Then:
1. Pin zonai_sync and zonai_sync_drift to the release (tag or pub) instead of `feat/zonai-sync-drift`. Bump zonai_client to the version exporting `ServerException`, and drop Rubric's direct `revali_client` dependency if `SecureTokenStorage` no longer needs it.
2. Move `server/` to the new zonai_schema and CLI. #45's count fix applies with no change. Add `viewScope` (owner_id = caller) to the owner-only row rules in `tool/gen/server_schema.py`: it restores plain-COUNT speed, and it turns an unscoped list into "your rows" instead of a 403.
3. Optionally adopt `$.revision` (#51, #60) per table, together with `ZonaiSyncCapabilities(serverRevisionTables: …)`. Deploy the server first, as the zonai_sync README says.
4. Re-run `tool/check.sh` and `tool/sync_e2e.sh` on the rubric-owner simulator and emulator.

**$.revision deferred (2026-09-30).** The client-maintained `rev` is correct as long as every write goes through zonai_sync, and in Rubric every write does. `$.revision` only adds protection against writes that bypass sync, such as the zonai dashboard. Adopting it means changing each table's `rev` column and listing the table in `serverRevisionTables`, with the server deployed first. That is worth doing before anything other than the app writes Rubric's data, but it isn't needed for multi-device sync.

**Verified on v0.10.0 (2026-09-30).** tool/check.sh passes (514 tests). The two-device run passed between the rubric-owner simulator and a second rubric-owner simulator, `rubric-owner iPhone 17 Pro (B)`. Both hold identical data: 3 classes, 47 students, 94 evaluations, 0 pending, 0 dead. The Android leg passed on 0.9.4; on v0.10.0 day, Flutter's machine-wide device scan hung before reaching the emulator, so that leg ran on the second simulator. Run dev servers with `zonai serve --release` until zonai #67 (the watcher-burst fix) is released.
