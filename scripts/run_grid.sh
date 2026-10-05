#!/bin/bash
# ClawMem context-surfacing wall-time grid. Endpoints: nomic-embed-text via Ollama (what the vaults
# were embedded with), qmd-query-expansion-1.7B on llama-server :8089 (ClawMem's default LLM),
# qwen3-reranker-0.6B-Q8_0 on llama-server :8090 (ClawMem's default reranker). Loopback only.
cd ~/clawmem-timing
export NODE_LLAMA_CPP_GPU=cuda RUNS=3
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
V37=$HOME/rootstock-refs/ClawMem/bin/clawmem
V42=$HOME/clawmem-timing/ClawMem/bin/clawmem
COMMON="CLAWMEM_PROFILE=deep CLAWMEM_ENABLE_AMEM=false CLAWMEM_EMBED_URL=http://localhost:11434 CLAWMEM_EMBED_MODEL=nomic-embed-text CLAWMEM_LLM_URL=http://127.0.0.1:8089"
RR=CLAWMEM_RERANK_URL=http://127.0.0.1:8090
NL=CLAWMEM_NO_LOCAL_MODELS=true
echo "== start $(date '+%F %T')  QIDS=$QIDS"
python3 time_hook.py v037-local     $V37 $COMMON
python3 time_hook.py v037-rerankurl $V37 $COMMON $RR
python3 time_hook.py v037-nolocal   $V37 $COMMON $NL
WATCH=1 python3 time_hook.py v042-local     $V42 $COMMON
WATCH=1 python3 time_hook.py v042-rerankurl $V42 $COMMON $RR
WATCH=1 python3 time_hook.py v042-nolocal   $V42 $COMMON $NL
# side arm: our September LLM (gemma3:12b over Ollama) with the reranker server, to show the expansion/rerank interaction
WATCH=1 python3 time_hook.py v042-rerankurl-gemma12b $V42 CLAWMEM_PROFILE=deep CLAWMEM_ENABLE_AMEM=false CLAWMEM_EMBED_URL=http://localhost:11434 CLAWMEM_EMBED_MODEL=nomic-embed-text CLAWMEM_LLM_URL=http://localhost:11434 CLAWMEM_LLM_MODEL=gemma3:12b $RR
echo "== DONE $(date '+%F %T')"
