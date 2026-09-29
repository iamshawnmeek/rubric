#!/usr/bin/env python3
"""Git merge driver for .arb (localization) files: a key-level union.

Parallel feature branches each ADD strings to lib/l10n/arb/app_en.arb, which
git sees as competing edits at the same end-of-object position — a conflict on
every merge, although no key is ever contested. This merges by key instead:

  * keys added on either side are kept (ours first, then theirs, in order);
  * a key changed on only one side takes that side's value;
  * a key changed DIFFERENTLY on both sides is a real conflict -> exit 1, and
    git falls back to reporting the file conflicted.

Registered by tool/setup.sh:  git config merge.arbunion.driver
    'python3 tool/arb_merge.py %O %A %B'
Stdlib only. Invoked as: arb_merge.py BASE OURS THEIRS (result written to OURS).
"""
import json
import sys
from collections import OrderedDict


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return OrderedDict()
    if not text.strip():
        return OrderedDict()
    return json.loads(text, object_pairs_hook=OrderedDict)


def main(base_path, ours_path, theirs_path):
    base, ours, theirs = load(base_path), load(ours_path), load(theirs_path)
    merged = OrderedDict(ours)
    conflicts = []
    for key, value in theirs.items():
        if key not in merged:
            if key in base and base[key] == value:
                continue  # deleted on our side, untouched on theirs
            merged[key] = value
        elif merged[key] != value:
            b = base.get(key)
            if b == merged[key]:
                merged[key] = value  # only theirs changed it
            elif b == value:
                pass  # only ours changed it
            else:
                conflicts.append(key)
    for key in list(merged):
        if key in base and key not in theirs and base[key] == merged[key]:
            del merged[key]  # deleted on theirs, untouched on ours
    if conflicts:
        sys.stderr.write("arb_merge: both sides changed: %s\n" % ", ".join(conflicts))
        return 1
    with open(ours_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, indent=2, ensure_ascii=False)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
