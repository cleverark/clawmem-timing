#!/bin/bash
# Pass 3: leg timings on an instrumented v0.37 copy; FTS-query experiment on a v0.42 copy; balanced profile reference.
cd ~/clawmem-timing
while ! grep -q "== DONE2" grid2.log; do sleep 20; done
export NODE_LLAMA_CPP_GPU=cuda
export QIDS="$(ls ~/pt/clawmem-q | head -10 | tr '\n' ' ')"
L37=$HOME/clawmem-timing/ClawMem-v037-legs/bin/clawmem
X42=$HOME/clawmem-timing/ClawMem-v042-ftsexp/bin/clawmem
V37=$HOME/rootstock-refs/ClawMem/bin/clawmem
V42=$HOME/clawmem-timing/ClawMem/bin/clawmem
BASE="CLAWMEM_ENABLE_AMEM=false CLAWMEM_EMBED_URL=http://localhost:11434 CLAWMEM_EMBED_MODEL=nomic-embed-text"
QMD="CLAWMEM_LLM_URL=http://127.0.0.1:8089"
GEM="CLAWMEM_LLM_URL=http://localhost:11434 CLAWMEM_LLM_MODEL=gemma3:12b"
RR=CLAWMEM_RERANK_URL=http://127.0.0.1:8090
echo "== start3 $(date '+%F %T')"
RUNS=1 python3 time_hook.py legs-v037-local-gemma12b     $L37 CLAWMEM_PROFILE=deep $BASE $GEM
RUNS=1 python3 time_hook.py legs-v037-rerankurl-gemma12b $L37 CLAWMEM_PROFILE=deep $BASE $GEM $RR
RUNS=1 python3 time_hook.py legs-v037-nolocal-gemma12b   $L37 CLAWMEM_PROFILE=deep $BASE $GEM CLAWMEM_NO_LOCAL_MODELS=true
RUNS=1 python3 time_hook.py legs-v037-local-qmd          $L37 CLAWMEM_PROFILE=deep $BASE $QMD
RUNS=3 WATCH=1 python3 time_hook.py v042x-rerankurl-andnostop $X42 CLAWMEM_PROFILE=deep $BASE $QMD $RR CLAWMEM_EXP_FTS=and-nostop
RUNS=3 WATCH=1 python3 time_hook.py v042x-rerankurl-or        $X42 CLAWMEM_PROFILE=deep $BASE $QMD $RR CLAWMEM_EXP_FTS=or
RUNS=3 WATCH=1 python3 time_hook.py v042-balanced             $V42 CLAWMEM_PROFILE=balanced $BASE $QMD $RR
RUNS=3 python3 time_hook.py v037-balanced                     $V37 CLAWMEM_PROFILE=balanced $BASE $QMD $RR
echo "== DONE3 $(date '+%F %T')"
