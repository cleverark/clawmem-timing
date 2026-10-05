#!/usr/bin/env python3
"""Pass 5: controlled re-measurement after crucible round 1.

Differences from time_hook.py (passes 1-4):
- Arms are INTERLEAVED: for each question and each round, every arm runs once, in a shuffled order
  (seeded, so it is reproducible). Host drift therefore hits all arms alike.
- Every call records the 1-minute load average and GPU utilisation from just before it.
- Every call records the document paths that were injected, so injection and evidence can be checked
  from the JSONL alone. Evidence means a LongMemEval evidence session, `conversations/answer_*`.
- Prompt modes: `own` is the vault's own question. `offtopic` is the question of a different vault in the
  set, whose evidence sessions are not in this vault. `gibberish` is one of three fixed nonsense strings.
- STRIP_HANDOFF=1 marks the vault's `_clawmem` documents (the one handoff note from our September run)
  inactive and invalidated in the copy before the call.

Usage: time_pass5.py <phase-name> <arms.json>
arms.json: a list of {"name", "bin", "watch": bool, "env": {..}}. Results go to results/pass5-<phase>.jsonl.
"""
import json, os, random, re, shutil, signal, sqlite3, subprocess, sys, time
from pathlib import Path

PHASE, ARMS_FILE = sys.argv[1], sys.argv[2]
ARMS = json.load(open(ARMS_FILE))
RUNS = int(os.environ.get("RUNS", "3"))
HOOK_TIMEOUT = int(os.environ.get("HOOK_TIMEOUT", "120"))  # a hang is recorded as a result (timed_out=true), not a crash
MODE = os.environ.get("PROMPT_MODE", "own")
STRIP = os.environ.get("STRIP_HANDOFF") == "1"
QIDS = os.environ["QIDS"].split()
ROOT = Path.home() / "clawmem-timing"
OUT = ROOT / "results" / f"pass5-{PHASE}.jsonl"
OUT.parent.mkdir(parents=True, exist_ok=True)
GIBBERISH = ["zorvath plinkety quaster mubble fennix drovel", "the arbitrary teapot sings glumly beneath purple cartography",
             "xq vbn trelk opsum wadgely farnish brimple"]

data = {q["question_id"]: q for q in json.load(open(Path.home() / "agent-memory/companion/pubbench/data/longmemeval_s_cleaned.json"))}
base = {k: v for k, v in os.environ.items() if not k.startswith("CLAWMEM_") and k != "INDEX_PATH"}
base["PATH"] = f"{Path.home()}/node/bin:{Path.home()}/.bun/bin:" + base["PATH"]
PATH_RE = re.compile(r"^(conversations|_clawmem|handoffs)/\S+\.md$|^\S+/\S+\.md$", re.M)


def prompt_for(i, qid, run):
    if MODE == "own":
        return data[qid]["question"]
    if MODE == "offtopic":
        return data[QIDS[(i + 5) % len(QIDS)]]["question"]
    return GIBBERISH[(i + run) % len(GIBBERISH)]


def host_state():
    load = os.getloadavg()[0]
    try:
        gpu = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        gpu = ""
    return round(load, 2), gpu


def watcher(binp, env):
    w = subprocess.Popen([binp, "watch"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, start_new_session=True)
    for _ in range(60):
        time.sleep(0.5)
        if subprocess.run([binp, "vec-daemon-health"], env=env, capture_output=True).returncode == 0:
            return w
    kill(w)
    raise RuntimeError("vector daemon never came up")


def kill(w):
    try:
        os.killpg(w.pid, signal.SIGTERM); w.wait(timeout=10)
    except Exception:
        try: os.killpg(w.pid, signal.SIGKILL)
        except Exception: pass


rng = random.Random(f"{PHASE}-{MODE}")
with OUT.open("a") as out:
    for i, qid in enumerate(QIDS):
        for run in range(1, RUNS + 1):
            order = ARMS[:]
            rng.shuffle(order)
            for arm in order:
                vault = ROOT / "vaults" / f"p5-{PHASE}-{MODE}{'-strip' if STRIP else ''}" / arm["name"] / f"{qid}-r{run}"
                shutil.rmtree(vault, ignore_errors=True)
                (vault / "config").mkdir(parents=True)
                shutil.copy(Path.home() / f"pt/clawmem-q/{qid}/cache/clawmem/index.sqlite", vault / "index.sqlite")
                if STRIP:
                    db = sqlite3.connect(vault / "index.sqlite")
                    db.execute("UPDATE documents SET active=0, invalidated_at=datetime('now') WHERE collection='_clawmem'")
                    db.commit(); db.close()
                env = dict(base, **arm["env"], INDEX_PATH=str(vault / "index.sqlite"),
                           CLAWMEM_CONFIG_DIR=str(vault / "config"), CLAWMEM_HOOK_DEDUP_WINDOW_SEC="0")
                w = watcher(arm["bin"], env) if arm.get("watch") else None
                prompt = prompt_for(i, qid, run)
                payload = json.dumps({"session_id": f"p5-{PHASE}-{arm['name']}-{qid}-{run}",
                                      "hook_event_name": "UserPromptSubmit", "prompt": prompt})
                load, gpu = host_state()
                timed_out = False
                try:
                    t0 = time.perf_counter()
                    h = subprocess.Popen([arm["bin"], "hook", "context-surfacing"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.PIPE, text=True, env=env, cwd=vault, start_new_session=True)
                    try:
                        so, se = h.communicate(payload, timeout=HOOK_TIMEOUT)
                    except subprocess.TimeoutExpired:
                        timed_out = True
                        os.killpg(h.pid, signal.SIGKILL)
                        so, se = h.communicate()
                    wall = time.perf_counter() - t0
                    p = subprocess.CompletedProcess(h.args, h.returncode, so, se)
                finally:
                    if w: kill(w)
                (vault / "hook.stderr").write_text(p.stderr)
                (vault / "hook.stdout").write_text(p.stdout)
                try:
                    ctx = json.loads(p.stdout)["hookSpecificOutput"]["additionalContext"]
                except Exception:
                    ctx = ""
                paths = [m.group(0) for m in PATH_RE.finditer(ctx)]
                legs = re.findall(r"\[legs\] (.*)", p.stderr)
                rec = {"phase": PHASE, "mode": MODE, "strip_handoff": STRIP, "arm": arm["name"], "qid": qid, "run": run,
                       "prompt": prompt, "wall_s": round(wall, 3), "rc": p.returncode, "timed_out": timed_out, "load1": load, "gpu_util": gpu,
                       "context_chars": len(ctx), "injected": bool(ctx), "injected_paths": paths,
                       "evidence": any("answer_" in x for x in paths), "legs": legs,
                       "stderr_head": "\n".join(l for l in p.stderr.splitlines() if "[legs]" not in l)[:300]}
                out.write(json.dumps(rec) + "\n"); out.flush()
                print(f"{PHASE} {MODE} {arm['name']:16s} {qid} r{run} {wall:6.2f}s inj={len(paths)} ev={rec['evidence']} load={load} gpu={gpu}", flush=True)
