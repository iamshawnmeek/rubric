# rubric_server

Rubric's [zonai](https://zonai.dev) backend: teacher accounts plus the synced
tables (rubrics, courses, students, assignments, evaluations, comment
snippets). Every synced table is owner-scoped, revisioned and tombstoned, as
`zonai_sync` requires.

Tables and rules are generated from `tool/gen/server_schema.py` -- edit the
spec there, then run it and `dart format server`.

```bash
cd server
zonai compile && zonai db migrate apply
zonai serve --port 8792 --host 0.0.0.0   # 0.0.0.0 so the Android emulator (10.0.2.2) can reach it
```
