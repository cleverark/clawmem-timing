#!/bin/bash
# Pass 5 (after crucible round 1). Rerank server :8090 is STOPPED for phase A and restarted for phase B.
# Note: bin/clawmem exports CLAWMEM_RERANK_URL=${CLAWMEM_RERANK_URL:-http://localhost:8090}, so an "unset" URL
# reaches whatever listens on :8090 — phase A therefore needs the port closed, not just the variable unset.
cd ~/clawmem-timing
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
RR_CMD="llama.cpp/build/bin/llama-server -m $HOME/.cache/qmd/models/hf_ggml-org_qwen3-reranker-0.6b-q8_0.gguf --reranking --port 8090 --host 127.0.0.1 -ngl 99 -c 2048 --batch-size 512"
echo "== start5 $(date '+%F %T')"
kill "$(cat rerank.pid)" 2>/dev/null; for i in $(seq 1 20); do kill -0 "$(cat rerank.pid)" 2>/dev/null || break; sleep 0.5; done
if curl -s -m 2 localhost:8090/health >/dev/null; then echo "ABORT: :8090 still answering"; exit 1; fi
echo "== phase A (no reranker reachable) $(date '+%T')"
RUNS=3 PROMPT_MODE=own python3 time_pass5.py A pass5/arms-A-server-down.json
setsid nohup $RR_CMD > rerank-server.log 2>&1 < /dev/null & echo $! > rerank.pid
for i in $(seq 1 60); do sleep 1; curl -s -m 2 localhost:8090/health | grep -q ok && break; done
curl -s localhost:8090/health | grep -q ok || { echo "ABORT: reranker did not come back"; exit 1; }
echo "== phase B (reranker up) $(date '+%T')"
RUNS=3 PROMPT_MODE=own       python3 time_pass5.py B pass5/arms-B-server-up.json
RUNS=1 PROMPT_MODE=offtopic  python3 time_pass5.py B pass5/arms-B-server-up.json
RUNS=1 PROMPT_MODE=gibberish python3 time_pass5.py B pass5/arms-B-server-up.json
RUNS=1 PROMPT_MODE=own STRIP_HANDOFF=1 python3 time_pass5.py B-strip pass5/arms-B-server-up.json
bash pass5/fts_hits.sh > results/pass5-fts-hits.txt 2>&1
echo "== DONE5 $(date '+%F %T')"
