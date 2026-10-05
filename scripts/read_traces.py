#!/usr/bin/env python3
"""Print the key fields of the newest surfacing trace in each traced vault (run on the measurement host)."""
import json, sqlite3, sys
from pathlib import Path
for arm in sys.argv[1:]:
    for v in sorted((Path.home() / "clawmem-timing/vaults" / arm).iterdir()):
        db = sqlite3.connect(v / "index.sqlite")
        row = db.execute("select trace_json from surfacing_diagnostics order by id desc limit 1").fetchone()
        if not row:
            print(arm, v.name, "NO TRACE"); continue
        t = json.loads(row[0]); a = t.get("admission") or {}; r = t.get("rerank") or {}
        ev = [s for s in r.get("scores", []) if "answer_" in s["filepath"]]
        evrej = [x["displayPath"] for x in a.get("rejected", []) if "answer_" in x["displayPath"]]
        print(f"{arm} {v.name} outcome={t['outcome']}/{t.get('emptyReason')} abstain={a.get('abstainReason')} kwAgreed={a.get('keywordAgreed')} "
              f"lanes={sorted({l['lane'] for l in (t.get('fusion') or {}).get('lanes', []) if isinstance(l, dict) and 'lane' in l})} "
              f"exp_variants={len((t.get('expansion') or {}).get('variants', []))} rerank_attempted={r.get('attempted')} "
              f"evidence_rerank_max={max((s['score'] for s in ev), default=None)} evidence_rejected={len(evrej)} escalationMs={round((t['timings'].get('escalationMs') or 0))}")
