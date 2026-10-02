# Rubric — working agreement

Rubric is a Flutter app for teachers: build weighted grading rubrics, grade a
whole class against them, and see how every objective is landing. Offline-first;
all data lives on the device (drift/SQLite).

## Commands

Always use `tool/flutter` (never bare `flutter`/`fvm flutter`): it runs the
repo-local SDK clone in `.sdk/flutter`, because another project's long-lived
`flutter run` holds the startup lock of the shared fvm SDK.

```bash
tool/setup.sh                       # once per clone: arb merge driver + pub get
tool/check.sh                       # the CI gate: analyze --fatal-infos + all tests
tool/flutter test test/features/x   # one area
tool/dart run build_runner build   # after changing lib/data/database.dart
```

`tool/check.sh` must be green before every commit. Infos are fatal.

## Layout

```
lib/
  app/            router, routes, shell (nav), settings — owned by rubric-owner
  design_system/  THE design system. Import `package:rubric/design_system/design_system.dart`
  domain/         pure Dart models + scoring. No Flutter imports.
  data/           drift database, repositories, shared providers
  features/<f>/   one directory per feature; screens, widgets, feature providers
  l10n/arb/       app_en.arb — every user-facing string
test/             mirrors lib/
```

## Rules

1. **The design system is fixed.** Colors come only from `design_system/colors.dart`,
   text only from `RubricTextStyles` / the typography widgets, spacing from
   `Insets`/`Corners`. No `Color(0x…)`, no ad-hoc `TextStyle(fontFamily: …)`, no
   Material default blue anywhere. Look: dark purple `secondary` background,
   `primaryCard` cards with a `CardHint` over a `CardTitle`, 10pt radius,
   orange `accent` CTAs docked bottom-centre (`AccentButton`/`NextButton`),
   `HeadlineOne` page titles under a `SmallLogo`, sheets via `showRubricSheet` +
   `RubricSheet`. Use `RubricPage` for every full page. If you need a new
   reusable component, add it to `design_system/components/` and export it.
2. **Every user-facing string goes in `lib/l10n/arb/app_en.arb`** and is read via
   `context.l10n`. Prefix keys with your feature (`gradingSaveLabel`). Add keys
   anywhere — a union merge driver (`tool/arb_merge.py`) merges parallel additions.
   Plurals/placeholders use ICU syntax.
3. **Domain logic is pure and tested.** Scoring lives in `domain/scoring.dart`;
   do not re-derive grades in widgets. Anything with arithmetic gets a unit test.
4. **Data access goes through repositories** in `lib/data/` and the providers in
   `lib/data/providers.dart`. Features may add their own providers in their own
   directory. The schema (`lib/data/database.dart`) is owned by rubric-owner — ask
   in `#rubric_owner` before changing it.
5. **Navigation uses `Routes.*`** from `lib/app/routes.dart`, never string literals.
   Routes are pre-registered for every feature; replace the stub page, keep its
   class name and constructor.
6. **Accessibility:** semantic labels on custom tappables, 48pt minimum targets,
   no information by color alone.
7. **Tests:** widget tests for each screen's main path (use
   `test/helpers/app_harness.dart`), unit tests for logic. A test must fail when
   the behaviour it names breaks.
8. Riverpod 3 (`Notifier`, `StreamProvider`), go_router, drift. No new
   dependencies without asking in `#rubric_owner`.

## Ownership and cost (standing, from Jonah, 2026-10-01)

> "You're the owner of this repository. You are capable of making the decisions
> you think are best for this project. Take this as a standing authorization for
> you to do what you think is right - keeping in mind real-world costs like
> memory, money, etc. Keep this as low of a cost as possible. Remember that we're
> building world-class, maintainable software and we have the capability of
> building ANYTHING that only requires software. If you find something that would
> cost a lot over time, but we can spent the time to build it up front, it's
> probably worth putting the feature on hold until we can build out the
> services / tooling we need. ... We do hard, challenging things and don't cut
> corners."

What this means in practice:
- rubric-owner decides and acts. It doesn't queue decisions for the human that
  are the owner's to make, and it pushes to origin once the checks pass.
- **Recurring cost is the expensive kind.** Prefer $0 running cost. When a
  feature would bring an ongoing bill (a paid service, a metered API, a
  hosting tier), first ask whether software we build once could replace it.
  If it could, hold the feature and build that tooling first.
- Count memory, disk, CPU and the shared machine (one heavy suite at a time)
  as costs too.
- No shortcuts. Every change is world-class and maintainable: tested,
  mutation-checked where it matters, documented where the next owner needs it.
- Still ask the human for anything outside this repo that is theirs: accounts,
  payment, signing up for services, and other repos' policies.

## Devices

Start and stop the Android emulator only with `tool/emulator.sh start|stop`, which uses hardware GPU rendering. Never use `-gpu swiftshader*`. Shut devices down when a run finishes; idle emulators cost the shared machine.

This project's agent only uses devices named `rubric-owner*` (iOS simulator
`rubric-owner iPhone 17 Pro`, Android AVD `rubric_owner_pixel`). Never touch the
physical SM-G892U or `emulator-5554` — they belong to other agents.
