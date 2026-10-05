#!/usr/bin/env python3
"""Summarize results/*.jsonl into one markdown table (median / p90 / max wall, injection rate)."""
import json, glob, statistics as st, sys
from pathlib import Path

rows = []
for f in sorted(glob.glob(str(Path(__file__).resolve().parent.parent / "results" / "*.jsonl"))):
    R = [json.loads(l) for l in open(f) if l.strip()]
    if not R:
        continue
    w = sorted(r["wall_s"] for r in R)
    p90 = w[max(0, -(-9 * len(w) // 10) - 1)]
    inj = sum(r["injected"] for r in R)
    rows.append((Path(f).stem, len(R), st.median(w), p90, max(w), f"{inj}/{len(R)}"))
print("| arm | n | median s | p90 s | max s | injected |\n|---|---|---|---|---|---|")
for a, n, m, p, x, i in rows:
    print(f"| {a} | {n} | {m:.2f} | {p:.2f} | {x:.2f} | {i} |")
