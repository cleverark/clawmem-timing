#!/bin/bash
# Pass 4: one traced call per question (CLAWMEM_SURFACING_TRACE=1) to back the mechanism claims. Not used for timing.
cd ~/clawmem-timing
export NODE_LLAMA_CPP_GPU=cuda RUNS=1 WATCH=1
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
V42=$HOME/clawmem-timing/ClawMem/bin/clawmem
BASE="CLAWMEM_ENABLE_AMEM=false CLAWMEM_EMBED_URL=http://localhost:11434 CLAWMEM_EMBED_MODEL=nomic-embed-text CLAWMEM_RERANK_URL=http://127.0.0.1:8090 CLAWMEM_SURFACING_TRACE=1"
python3 time_hook.py trace-v042-deep-qmd      $V42 CLAWMEM_PROFILE=deep $BASE CLAWMEM_LLM_URL=http://127.0.0.1:8089
python3 time_hook.py trace-v042-deep-gemma12b $V42 CLAWMEM_PROFILE=deep $BASE CLAWMEM_LLM_URL=http://localhost:11434 CLAWMEM_LLM_MODEL=gemma3:12b
python3 time_hook.py trace-v042-balanced-qmd  $V42 CLAWMEM_PROFILE=balanced $BASE CLAWMEM_LLM_URL=http://127.0.0.1:8089
echo "== DONE4"
