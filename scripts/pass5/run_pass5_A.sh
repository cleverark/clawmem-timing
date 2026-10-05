#!/bin/bash
# Phase A re-run (the first phase-A run died on an unhandled 180 s hang in v037-norr; kept as results/pass5-A-aborted.jsonl).
cd ~/clawmem-timing
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
RR_CMD="llama.cpp/build/bin/llama-server -m $HOME/.cache/qmd/models/hf_ggml-org_qwen3-reranker-0.6b-q8_0.gguf --reranking --port 8090 --host 127.0.0.1 -ngl 99 -c 2048 --batch-size 512"
echo "== startA2 $(date '+%F %T')"
kill "$(cat rerank.pid)" 2>/dev/null; for i in $(seq 1 20); do kill -0 "$(cat rerank.pid)" 2>/dev/null || break; sleep 0.5; done
if curl -s -m 2 localhost:8090/health >/dev/null; then echo "ABORT: :8090 still answering"; exit 1; fi
RUNS=3 PROMPT_MODE=own HOOK_TIMEOUT=120 python3 time_pass5.py A2 pass5/arms-A-server-down.json
setsid nohup $RR_CMD > rerank-server.log 2>&1 < /dev/null & echo $! > rerank.pid
for i in $(seq 1 60); do sleep 1; curl -s -m 2 localhost:8090/health | grep -q ok && break; done
echo "reranker restored: $(curl -s localhost:8090/health)"
echo "== DONEA2 $(date '+%F %T')"
