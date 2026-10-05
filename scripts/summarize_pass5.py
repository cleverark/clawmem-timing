#!/usr/bin/env python3
"""Rebuild the pass-5 tables in RESULTS.md from results/pass5-*.jsonl.

Statistics are grouped by (phase, prompt mode, arm) and never pooled across phases. The aborted first attempt at
phase A (pass5-A-aborted.jsonl) is reported only in the exit-status table.
Phases:
  C        all reranker configurations in one interleaved phase (primary for timing and reranker cost)
  A2       reranker server stopped
  B        reranker server running; also off-topic and gibberish controls
  B-strip  as B, with the vault's handoff document deactivated
"""
import glob, json, re, statistics as st
from collections import Counter, defaultdict
from pathlib import Path

RES = Path(__file__).resolve().parent.parent / "results"
rows = []
for f in sorted(glob.glob(str(RES / "pass5-*.jsonl"))):
    rows += [dict(json.loads(l), _file=Path(f).name) for l in open(f) if l.strip()]
main = [r for r in rows if "aborted" not in r["_file"]]


def p90(xs):
    xs = sorted(xs)
    return xs[max(0, -(-9 * len(xs) // 10) - 1)]


def leg(rs, key):
    return [int(m.group(1)) for r in rs for l in r["legs"] for m in [re.search(key + r"=(\d+)", l)] if m]


g = defaultdict(list)
for r in main:
    g[(r["phase"], r["mode"], r["arm"])].append(r)

print("## Wall time, injection and evidence (questions are x/10; repeat calls are nearly deterministic)\n")
print("| phase | prompts | arm | calls | median s | p90 s | max s | questions injected | questions w/ evidence | mean items | median load1 |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for (ph, mo, arm), rs in sorted(g.items()):
    w = [r["wall_s"] for r in rs]
    nq = len({r["qid"] for r in rs})
    print(f"| {ph} | {mo} | {arm} | {len(rs)} | {st.median(w):.2f} | {p90(w):.2f} | {max(w):.2f} | "
          f"{len({r['qid'] for r in rs if r['injected']})}/{nq} | {len({r['qid'] for r in rs if r['evidence']})}/{nq} | "
          f"{st.mean(len(r['injected_paths']) for r in rs):.1f} | {st.median(r['load1'] for r in rs):.2f} |")

print("\n## v0.37 legs (instrumented copy), own prompts, per phase\n")
print("| phase | arm | calls | reranker ran | store.rerank ms min / median / max | remote expansion ms median |")
print("|---|---|---|---|---|---|")
for (ph, mo, arm), rs in sorted(g.items()):
    if mo != "own" or not arm.startswith("v037"):
        continue
    rr, ex = leg(rs, "rerank_ms"), leg(rs, "expand_remote_ms")
    rr_s = f"{min(rr)} / {st.median(rr):.0f} / {max(rr)}" if rr else "—"
    print(f"| {ph} | {arm} | {len(rs)} | {len(rr)}/{len(rs)} | {rr_s} | {st.median(ex):.0f} |" if ex else f"| {ph} | {arm} | {len(rs)} | {len(rr)}/{len(rs)} | {rr_s} | — |")

print("\n## Exit status (every file, including the aborted attempt)\n")
c = Counter((r["_file"], r["arm"], r["rc"], bool(r.get("timed_out"))) for r in rows)
print("| file | arm | rc | timed out | calls |\n|---|---|---|---|---|")
for (f, arm, rc, to), n in sorted(c.items(), key=str):
    if rc != 0 or to:
        print(f"| {f} | {arm} | {rc} | {to} | {n} |")
print("\nAll other calls exited 0. The aborted attempt's one unrecorded call was killed by the first harness's 180 s timeout (results/grid5.log).")
