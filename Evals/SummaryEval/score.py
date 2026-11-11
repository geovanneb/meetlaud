#!/usr/bin/env python3
"""Scores a SummaryEval run, and shows what the model wrote.

  python3 -I score.py <run.jsonl>                          scores, overall and by group
  python3 -I score.py <run.jsonl> --like <other.jsonl>     only the cases both runs have, to compare fairly
  python3 -I score.py <run.jsonl> --show <meeting> <target> <template id>
"""
import collections
import json
import re
import sys

NAMES = {"Ana", "Bruno", "Carla", "Marina", "Pedro", "Lucas", "Rafaela", "Lucía", "Javier", "Elena", "佐藤", "鈴木", "田中"}


def load(path):
    return [json.loads(line) for line in open(path, encoding="utf-8")]


def prefixed(text):
    """An item that starts like a transcript line: "Pedro: ..." or "Speaker 2: ..."."""
    match = re.match(r"^\s*([^\s:：]{1,12}(?: \d+)?)\s*[:：]", text)
    return bool(match and (match.group(1) in NAMES or match.group(1).startswith("Speaker")))


def score(rows, key=lambda row: "all"):
    groups = collections.defaultdict(collections.Counter)
    for row in rows:
        counter = groups[key(row)]
        counter["cases"] += 1
        counter["seconds"] += row["seconds"]
        counter["empty"] += len(row["emptySections"])
        counter["errors"] += row.get("error") is not None
        for item in row["items"]:
            counter["items"] += 1
            counter["wrong"] += not item["rightLanguage"]
            counter["copied"] += item["copied"]
            counter["prefixed"] += prefixed(item["text"])
            counter["review"] += item["needsReview"]
    for name, c in sorted(groups.items()):
        n = max(c["items"], 1)
        print(
            f"{name:22} cases {c['cases']:3}  items {c['items']:4}  wrong language {100 * c['wrong'] / n:5.1f}%  "
            f"copied {100 * c['copied'] / n:5.1f}%  'Name:' {100 * c['prefixed'] / n:5.1f}%  "
            f"review {100 * c['review'] / n:5.1f}%  empty sections {c['empty']:3}  errors {c['errors']}  "
            f"{c['seconds'] / c['cases']:.0f}s per case"
        )


def show(rows, meeting, target, template):
    for row in rows:
        if (row["meeting"], row["target"], row["template"]) != (meeting, target, template):
            continue
        section = None
        for item in row["items"]:
            if item["section"] != section:
                section = item["section"]
                print(f"## {section}")
            time = f"[{int(item['time'])}]" if item.get("time") is not None else "[-]"
            task = f"  ({item.get('owner') or '-'} | {item.get('due') or '-'})" if item.get("owner") or item.get("due") else ""
            flags = ("" if item["rightLanguage"] else " <WRONG LANGUAGE>") + (" <REVIEW>" if item["needsReview"] else "")
            print(f"  {time} {item['text']}{task}{flags}")
        print("empty sections:", ", ".join(row["emptySections"]) or "none")


rows = load(sys.argv[1])
if "--show" in sys.argv:
    index = sys.argv.index("--show")
    show(rows, *sys.argv[index + 1 : index + 4])
    sys.exit()
if "--like" in sys.argv:
    keep = {(r["meeting"], r["target"], r["template"]) for r in load(sys.argv[sys.argv.index("--like") + 1])}
    rows = [r for r in rows if (r["meeting"], r["target"], r["template"]) in keep]
print("== overall"); score(rows)
print("== by output language"); score(rows, lambda r: r["target"])
print("== by meeting"); score(rows, lambda r: r["meeting"])
print("== output language differs from the meeting"); score([r for r in rows if r["target"] not in ("auto", r["meeting"])])
print("== by template"); score(rows, lambda r: r["template"])
