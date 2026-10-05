#!/bin/bash
# Follow-up: v0.37 with our September LLM (gemma3:12b over Ollama), to separate the expansion leg from the rerank leg.
cd ~/clawmem-timing
while ! grep -q "== DONE" grid.log; do sleep 20; done
export NODE_LLAMA_CPP_GPU=cuda RUNS=3
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
V37=$HOME/rootstock-refs/ClawMem/bin/clawmem
G="CLAWMEM_PROFILE=deep CLAWMEM_ENABLE_AMEM=false CLAWMEM_EMBED_URL=http://localhost:11434 CLAWMEM_EMBED_MODEL=nomic-embed-text CLAWMEM_LLM_URL=http://localhost:11434 CLAWMEM_LLM_MODEL=gemma3:12b"
echo "== start2 $(date '+%F %T')"
python3 time_hook.py v037-local-gemma12b     $V37 $G
python3 time_hook.py v037-rerankurl-gemma12b $V37 $G CLAWMEM_RERANK_URL=http://127.0.0.1:8090
python3 time_hook.py v037-nolocal-gemma12b   $V37 $G CLAWMEM_NO_LOCAL_MODELS=true
WATCH=1 python3 time_hook.py v042-local-gemma12b $HOME/clawmem-timing/ClawMem/bin/clawmem $G
echo "== DONE2 $(date '+%F %T')"
