#!/usr/bin/env python3
"""Wall-time ClawMem's context-surfacing hook run by hand, one fresh process per prompt.

Usage: [RUNS=3] [QIDS="..."] [WATCH=1] time_hook.py <arm> <clawmem_bin> KEY=VAL ...

Every call gets a FRESH copy of the per-question vault from our September deep run
(~/pt/clawmem-q/<qid>), so nothing carries between calls: no hook_dedupe row, no rerank-score
cache, no prior surfacing state. Prompt = the question text verbatim.
WATCH=1 starts `clawmem watch` on the copy (same build) and waits for `vec-daemon-health` = live
before the timed call, then kills it — the vector-daemon deployment the v0.38+ docs describe.
Wall time is measured around the hook subprocess only (watcher startup excluded).
"""
import json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

ARM, BIN, *KV = sys.argv[1:]
RUNS = int(os.environ.get("RUNS", "3"))
QIDS = os.environ["QIDS"].split()
WATCH = os.environ.get("WATCH") == "1"
ROOT = Path.home() / "clawmem-timing"
OUT = ROOT / "results" / f"{ARM}.jsonl"
OUT.parent.mkdir(parents=True, exist_ok=True)

data = {q["question_id"]: q for q in json.load(open(Path.home() / "agent-memory/companion/pubbench/data/longmemeval_s_cleaned.json"))}

base_env = {k: v for k, v in os.environ.items() if not k.startswith("CLAWMEM_") and k != "INDEX_PATH"}
base_env["PATH"] = f"{Path.home()}/node/bin:{Path.home()}/.bun/bin:" + base_env["PATH"]
base_env.update(dict(kv.split("=", 1) for kv in KV))


def start_watcher(env):
    w = subprocess.Popen([BIN, "watch"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, start_new_session=True)
    for _ in range(60):
        time.sleep(0.5)
        if subprocess.run([BIN, "vec-daemon-health"], env=env, capture_output=True).returncode == 0:
            return w
    stop_watcher(w)
    raise RuntimeError("vector daemon never came up")


def stop_watcher(w):
    try:
        os.killpg(w.pid, signal.SIGTERM)
        w.wait(timeout=10)
    except Exception:
        try: os.killpg(w.pid, signal.SIGKILL)
        except Exception: pass


with OUT.open("w") as out:
    for qid in QIDS:
        q = data[qid]
        for run in range(1, RUNS + 1):
            vault = ROOT / "vaults" / ARM / f"{qid}-r{run}"
            shutil.rmtree(vault, ignore_errors=True)
            (vault / "config").mkdir(parents=True)
            shutil.copy(Path.home() / f"pt/clawmem-q/{qid}/cache/clawmem/index.sqlite", vault / "index.sqlite")
            env = dict(base_env, INDEX_PATH=str(vault / "index.sqlite"), CLAWMEM_CONFIG_DIR=str(vault / "config"),
                       CLAWMEM_HOOK_DEDUP_WINDOW_SEC="0")
            w = start_watcher(env) if WATCH else None
            payload = json.dumps({"session_id": f"timing-{ARM}-{qid}-{run}", "hook_event_name": "UserPromptSubmit",
                                  "prompt": q["question"]})
            try:
                t0 = time.perf_counter()
                p = subprocess.run([BIN, "hook", "context-surfacing"], input=payload, capture_output=True, text=True,
                                   env=env, timeout=120, cwd=vault)
                wall = time.perf_counter() - t0
            finally:
                if w: stop_watcher(w)
            (vault / "hook.stderr").write_text(p.stderr)
            (vault / "hook.stdout").write_text(p.stdout)
            try:
                ctx = json.loads(p.stdout)["hookSpecificOutput"]["additionalContext"]
            except Exception:
                ctx = ""
            rec = {"arm": ARM, "qid": qid, "run": run, "wall_s": round(wall, 3), "rc": p.returncode,
                   "context_chars": len(ctx), "injected": len(ctx) > 0, "stderr_tail": p.stderr.strip()[-400:]}
            out.write(json.dumps(rec) + "\n"); out.flush()
            print(f"{ARM} {qid} r{run} {wall:6.2f}s rc={p.returncode} ctx={len(ctx)}", flush=True)
