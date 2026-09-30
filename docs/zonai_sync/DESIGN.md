# zonai_sync: standard offline sync for zonai apps

Status: proposal, 2026-09-29. Author: rubric-owner. First consumer: Rubric.
Evidence: the zonai v0.9.4 source, and the sync code in gravity_brew, wholesale-command-station, gents and flyby.

## Problem

Every Flutter app on zonai that must work offline builds its own sync. gravity_brew
is the only one that has done it so far. Each synced table costs about 900 lines, of
which about 700 are sync plumbing: the same field written in roughly ten places. A
read-only review found five correctness bugs in that engine. Each one comes from a
zonai behaviour an app author can't be expected to know:

| Bug class | zonai behaviour behind it |
|---|---|
| Rows that are never updated after creation are never pulled | a nullable `updated_at` is NULL on insert, and `NULL > cursor` is never true |
| A whole pull fails with 403 once another user's row passes the cursor | a list fails completely if any single row fails `canView` |
| Every member's push fails with 403 | table-level `canUpdate` is checked before the row lookup, so update-then-create never reaches create |
| Last-write-wins compares two different clocks | the server silently ignores client writes to `updated_at` |
| A new account inherits the old account's outbox and cursors | nothing to do with zonai; nobody owns the "account scope" of local state |

A standard library fixes all of these once, by construction.

## Constraints from zonai (v0.9.4)

- **No plugin mechanism.** The server is a fixed revali app. Project code is found by
  directory (`zonai.yaml` paths) and each table gets exactly one `Extension` and one
  `TableOperations`; a second one throws. A package can therefore ship **base classes
  and mixins** that a project extends in its single slot, plus tables the project
  re-exports. It cannot add HTTP routes.
- **Operations never see the JWT.** `_query` drops it, so a scope filter can't be
  injected on the server. Scoping today happens by refusal: a list returns 403 when
  any row is denied.
- **Count leak.** `/db/count` and `list?limit=0` check only table-level `canList`. That
  exposes other owners' row counts under any `where`.
- **Duplicate ids return 409.** A create with a client-chosen id is retry-safe.
- **Conditional update half-exists.** An update whose `where` includes `rev = N` returns
  404 on a mismatch, which can't be told apart from a deleted or hidden row.
- **Writes are serialised in one process.** A `MAX+1` sequence in core would be
  gap-free and commit-ordered.
- **Streams** (SSE) invalidate by table dependency and filter denied rows. The client
  swallows errors and never reconnects.
- **`.zonai/schema.json`** records every table and column, with its kind,
  nullability, foreign keys and enum values. That makes it a single source of truth
  that code generation can read.

## Design

### Principles
1. **The local database is the source of truth.** The UI reads only local tables. The
   network is a background concern and the app is fully usable offline.
2. **One clock for ordering.** Only server-assigned values order changes: the cursor
   and `rev`. The client clock is never compared with the server's.
3. **Scope is part of every query.** Every pull carries `owner = me`, or the table's
   scope. The library adds it; the app author doesn't write it.
4. **Account-scoped state.** The outbox, cursors and synced rows belong to one user.
   Signing out or switching accounts clears them atomically.
5. **Nothing is silently dropped.** Every failure is classified. A permanent failure
   goes to a dead-letter queue the UI can show, retry or discard.

### Server side: `zonai_sync_schema` (package; depends only on `zonai_schema`)

```dart
final class TastingNoteTable extends Table<TastingNote> with Syncable<TastingNote> {
  TastingNoteTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: NoteId.new),
      ownerId = $.text('owner_id', (s) => s.ownerId),
      body = $.text('body', (s) => s.body),
      sync = $.syncColumns();          // updated_at (non-null), rev, deleted_at
  @override String get ownerColumn => 'owner_id';
}
// operations/tasting_notes.dart (the table's single slot)
SyncOperations<TastingNoteTable, TastingNote> main() => SyncOperations(tastingNotes);
// rules/*.dart
SyncTableRules<TastingNoteTable, TastingNote> main() => SyncTableRules.owned(tastingNotes);
SyncRowRules<TastingNoteTable, TastingNote>  main() => SyncRowRules.owned(tastingNotes);
```

The package provides:

- **`$.syncColumns()`** adds a non-null `updated_at` (so inserts are stamped), a `rev`
  that increments on every update, and a `deleted_at` tombstone.
- **`SyncOperations`** hides tombstones from ordinary lists and increments `rev` on
  update. Sync pulls opt in to seeing tombstones.
- **`SyncTableRules.owned` / `SyncRowRules.owned`**:
  - table-level `canUpdate` and `canDelete` are allowed for signed-in users, so the
    row rule decides (this fixes the 403-before-lookup bug class);
  - `canCreate`, `canView` and `canUpdate` require `owner == jwt.userId`, checked on
    both `before` and `after`, so a row can't be reassigned;
  - hard deletes are denied; clients use tombstones.
- **`TombstoneGcCron`** purges old tombstones after a configurable horizon. A client
  whose cursor is older than the horizon does a full resync.
- **Shared-access helpers** for later (a shares table checked from rules with
  `get.*`).

### Client side: `zonai_sync` (Flutter/Dart, drift)

```dart
final sync = ZonaiSync(
  client: zonaiClient,
  database: appDb,                       // any drift GeneratedDatabase
  tables: [TastingNotesSync(), ...],     // generated (see below) or hand-written
  scope: SyncScope.owner(() => auth.userId),
);
await sync.start();                      // pull, subscribe to pokes, drain outbox
await sync.write(tastingNotes, note);    // local write + outbox entry, one transaction
await sync.delete(tastingNotes, id);     // local tombstone + outbox entry
sync.status;                             // Stream<SyncStatus>: per table, pending, dead letters
await sync.signOut();                    // clears rows, outbox, cursors atomically
```

**Parts:**

- **`SyncTable<T>` descriptor:** table name, id, wire and local codecs, owner or scope
  column, mode (`bidirectional`, `pullOnly` or `pushOnly`), parents (for push
  ordering) and conflict policy.
- **Outbox:** a drift table owned by the library. Entry fields: `{id, table, rowId,
  op, payload, baseRev, schemaVersion, attempts, state(pending|dead), lastError,
  queuedAt}`. Behaviour:
  - Entries coalesce per row: a delete after an unpushed create cancels both.
  - The row write and the enqueue happen in one transaction.
  - Pushes go out in parent-first order.
- **Push:**
  - **create:** a `POST` with the client id. A 409 means it already exists, so fall
    through to update.
  - **update:** conditional on `baseRev`. With no match it re-reads by id to tell
    conflict, deleted and forbidden apart, then applies the table's `ConflictPolicy`.
  - **delete:** a tombstone update.
  - Batched through `POST /db/batch` once core supports it (core PR 6).
- **Pull:** per table, `where scope AND (updated_at, id) > cursor`, keyset-paged in
  ascending order. It re-reads a small overlap window because server clock steps
  can't be ruled out. Each page is applied in one transaction together with the new
  cursor. Tombstones delete locally. Once core PR 2 lands, the cursor becomes the
  gap-free `seq` and the overlap window goes away.
- **Conflict policies:**
  - `serverWins` (the default);
  - `clientWins`, which re-pushes with the new `baseRev`;
  - `merge(local, server, base)`, which gets the common ancestor and allows
    field-level merges (for example, per-criterion scores in Rubric's evaluations);
  - `lastWriteWins`, which uses `rev` and never a timestamp.
- **Error classifier:**

  | Failure | Handling |
  |---|---|
  | offline or timeout | retry with backoff |
  | 401 | pause and ask the app to re-authenticate |
  | 403, 400 or 422 | dead-letter |
  | 409 | conflict path |
  | 429 | wait for `Retry-After` |
  | 5xx | back off |

- **Scheduler:** runs on local write, reconnect, app resume, a periodic reconcile
  (default 5 min) and live pokes. A trigger that arrives during a sync is queued,
  never dropped. There is also a throttle.
- **Live channel:** an SSE `stream/count` on each scoped table is used only as a poke
  that triggers a pull. It reconnects with backoff, re-authenticates, and reframes
  concatenated JSON itself, using wholesale-command-station's brace-depth framing.
- **Codegen (`zonai_sync_gen`):** reads `.zonai/schema.json` and emits drift tables,
  wire and local codecs and `SyncTable` descriptors. Adding a synced table becomes:
  write the zonai schema, run codegen, register it.

### Core zonai PRs (generic features; each useful without sync)

| # | Change | Why | Size |
|---|---|---|---|
| 1 | JWT-aware scope for list, count and read, and count respects it | closes the count leak; the server enforces scope instead of refusing | S–M |
| 2 | `$.sequence()` and `$.revision()` auto-maintained columns | a gap-free cursor, and `rev` without per-project overrides | M |
| 3 | Precondition on update (`expect: {rev: N}`) returns 409 with the current row | tells a conflict apart from a deleted or forbidden row | S–M |
| 4 | `isSyncable` / column kinds in `schema.json` | lets codegen find synced tables | S |
| 5 | `GET /db/changes?since=…` for many tables, no count, including tombstones | one round trip per sync instead of one per table, each with a COUNT | M |
| 6 | `POST /db/batch`: transactional mixed mutations with a result per item | atomic multi-row pushes and fewer requests | L |
| 7 | Rate-limit key per user, not only per IP | a whole school behind one NAT shares one budget | S–M |

The packages work on **today's** zonai without these PRs. Each PR, once released, is
detected and used automatically.

## Where it lives

`zonai_sync_schema`, `zonai_sync` and `zonai_sync_gen` should live in the zonai
monorepo under `libs/`. There they share zonai's e2e harness, which starts a real
server from a fixture project, and its release train. That fixes the version-coupling
problems every consumer has hit so far. Until the maintainer agrees, they can be
developed as a pub workspace in Rubric with the same layout and moved later without
API changes.

## Testing

- Unit tests with in-memory drift and a fake remote for the whole state machine:
  coalescing, ordering, classification, conflicts, account switching.
- An e2e fixture against a real zonai server, with two simulated devices and one user:
  - offline edits on both devices, then reconnect;
  - a delete racing an edit;
  - 1,000+ rows paged;
  - a restart in the middle of a pull;
  - an account switch.
- Regression tests for each of gravity_brew's five bugs. Each must fail when the
  guard it covers is removed.

## Migration for existing apps

- **gravity_brew:** swap its `packages/sync` and `remote_db_zonai` for `zonai_sync`,
  keeping its domain repositories. Its server schemas adopt `$.syncColumns()` through
  one migration that backfills `updated_at = created_at` and `rev = 0`.
- **wholesale-command-station:** has no offline store. It can adopt the live channel on
  its own to replace its hand-written reconnect and polling.
