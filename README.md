# Rubric

**Grading made simple. Rubric your way.**

Rubric is a mobile app for teachers. Build weighted grading rubrics, grade a whole
class against them in minutes, give specific feedback, and see which objectives your
students are mastering. Everything is stored on the device, and the app works
fully offline.

## What it does

- **Rubric builder:** objectives → groups → weights → grading scale. Choose
  *Simple* (a percentage per objective) or *Detailed* (performance levels with
  descriptors, the classic rubric grid).
- **Template gallery:** ready-made rubrics across subjects to start from.
- **Classes & rosters:** add students by hand, paste a list, or import a CSV.
- **Assignments:** each one pins a snapshot of its rubric, so editing a rubric
  later never re-grades work you've already marked.
- **Fast grading:** tap a level or a score per objective and watch the grade update
  live. Includes a comment bank, late penalties, excused/missing, and overrides.
- **Gradebook & analytics:** a students × assignments grid, score distributions,
  objective mastery, and a "needs attention" list.
- **Export:** printable PDF rubrics and student feedback reports, CSV for your
  gradebook or LMS, and full JSON backup & restore.

## Design

The palette, Avenir typography and components come from the original design
system and live in [`lib/design_system/`](lib/design_system/). Every screen is
built from it. See [CLAUDE.md](CLAUDE.md) for the rules.

## Development

Requirements: macOS with Xcode, Android SDK, and [fvm](https://fvm.app).
Flutter 3.47.5 is pinned in [`.fvmrc`](.fvmrc).

```bash
tool/setup.sh        # once per clone: merge driver for strings + pub get
tool/check.sh        # what CI runs: analyze (infos fatal) + all tests
tool/flutter run     # run on a device or simulator
```

`tool/flutter` runs a private copy-on-write clone of the pinned SDK in `.sdk/`.
Another project's long-running `flutter run` on the shared fvm SDK holds that
SDK's startup lock, and the private clone means it can never block this
project.

After changing the database schema (`lib/data/database.dart`):

```bash
tool/dart run build_runner build
```

App icon and splash are generated from `assets/icon/` by
`tool/dart run flutter_launcher_icons` and
`tool/dart run flutter_native_splash:create`.

### Layout

| Path | What |
|---|---|
| `lib/app/` | app widget, router (go_router), navigation shell, settings |
| `lib/design_system/` | tokens, typography, shared components, theme |
| `lib/domain/` | pure Dart models, scoring, statistics, weights |
| `lib/data/` | drift/SQLite database, repositories, Riverpod providers |
| `lib/features/` | one directory per feature |
| `lib/l10n/arb/` | all user-facing strings |
