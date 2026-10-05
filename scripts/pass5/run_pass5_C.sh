#!/bin/bash
# Phase C (after crucible round 2): every reranker configuration in ONE interleaved phase. "No reranker" is an explicit
# URL to a closed port (:8091) instead of stopping :8090, so server and no-server arms can share a round.
cd ~/clawmem-timing
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
curl -s -m 2 localhost:8090/health | grep -q ok || { echo "ABORT: reranker :8090 not up"; exit 1; }
if curl -s -m 2 localhost:8091/health >/dev/null; then echo "ABORT: something answers on :8091"; exit 1; fi
echo "== startC $(date '+%F %T')"
RUNS=3 PROMPT_MODE=own HOOK_TIMEOUT=120 python3 time_pass5.py C pass5/arms-C-one-phase.json
echo "== DONEC $(date '+%F %T')"
