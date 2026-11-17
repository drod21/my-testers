"""Merges every results/<persona>/findings.json of a collected run into one
Markdown table, most severe first, with how many personas hit each issue.
Usage: python3 scripts/summarize.py <collected_run_dir>"""
import json, sys
from collections import defaultdict
from pathlib import Path

ORDER = {"blocker": 0, "major": 1, "minor": 2, "cosmetic": 3}
issues, scores = defaultdict(lambda: {"personas": set(), "sev": None, "where": set()}), []
for f in Path(sys.argv[1]).glob("*/results/*/findings.json"):
    persona = f.parent.name
    data = json.loads(f.read_text())
    if isinstance(data.get("score"), (int, float)):
        scores.append(data["score"])
    for i in data.get("issues", []):
        k = i.get("title", "?").strip().lower()
        e = issues[k]
        e["title"] = i.get("title", "?")
        e["personas"].add(persona)
        e["where"].add(i.get("screen", ""))
        if ORDER.get(i.get("severity"), 9) < ORDER.get(e["sev"], 9):
            e["sev"] = i.get("severity")
print(f"# Agent test summary\n\n{len(scores)} reports, average score "
      f"{sum(scores) / len(scores):.1f}/10\n" if scores else "# Agent test summary\n")
print("| Severity | Issue | Personas | Screen |\n|---|---|---|---|")
for e in sorted(issues.values(), key=lambda e: (ORDER.get(e["sev"], 9), -len(e["personas"]))):
    print(f"| {e['sev']} | {e['title']} | {len(e['personas'])} ({', '.join(sorted(e['personas']))}) | {', '.join(sorted(w for w in e['where'] if w))} |")
