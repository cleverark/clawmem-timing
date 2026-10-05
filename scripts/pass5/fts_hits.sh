#!/bin/bash
# Full-question FTS hit counts per vault (v0.37.0, v0.42.0 shipped, and the two experiment variants), --num 500 so the
# count is not capped by the CLI default of 10. Prints: qid version mode hits
cd ~/clawmem-timing; export PATH=$HOME/node/bin:$HOME/.bun/bin:$PATH
for qid in $(ls ~/pt/clawmem-q | head -10); do
  Q=$(python3 -c "import json;print([x for x in json.load(open('$HOME/agent-memory/companion/pubbench/data/longmemeval_s_cleaned.json')) if x['question_id']=='$qid'][0]['question'])")
  d=$(mktemp -d); cp ~/pt/clawmem-q/$qid/cache/clawmem/index.sqlite $d/; mkdir $d/config
  for spec in "v0.37.0:$HOME/rootstock-refs/ClawMem/bin/clawmem:" "v0.42.0:ClawMem/bin/clawmem:" "v0.42.0-exp:ClawMem-v042-ftsexp/bin/clawmem:and-nostop" "v0.42.0-exp:ClawMem-v042-ftsexp/bin/clawmem:or"; do
    IFS=: read -r ver bin mode <<< "$spec"
    n=$(env CLAWMEM_EXP_FTS=$mode INDEX_PATH=$d/index.sqlite CLAWMEM_CONFIG_DIR=$d/config $bin search --num 500 "$Q" 2>/dev/null | grep -cE '^  [^ ]+\.md$')
    echo "$qid $ver ${mode:-as-shipped} $n"
  done; rm -rf $d
done
