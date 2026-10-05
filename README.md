# ClawMem context-surfacing hook timings (follow-up to yoloshii/ClawMem#28)

Measurements and a reproduction for [yoloshii/ClawMem](https://github.com/yoloshii/ClawMem): wall times of the
`context-surfacing` hook (a follow-up to yoloshii/ClawMem#28), and a separate finding about v0.42 relevance admission. Start
with `repro/toy_repro.sh`, a four-note reproduction that needs no benchmark data, and `RESULTS.md`. These files
were written during review rounds before posting; `BUGS.md` lists the open low-severity notes.

The maintainer closed yoloshii/ClawMem#28 with v0.39.0 and asked, if the timeout came back, for two wall times of the
`context-surfacing` hook run by hand: once with `CLAWMEM_RERANK_URL` pointed at a reranker server, and
once with `CLAWMEM_NO_LOCAL_MODELS=true`. This repo collects those numbers on the current tag (v0.42.0).
It also times the individual legs on v0.37.0, which is consistent with where the original 25–39 s went, and records
a separate finding about v0.42 relevance admission that turned up along the way.

## Host

- DGX Spark: NVIDIA GB10, aarch64, driver 580.173.02
- Bun 1.2.23. Node 22 is on PATH for the `clawmem` wrapper.
- ClawMem v0.37.0, the checkout our yoloshii/ClawMem#28 numbers came from: node-llama-cpp 3.15.1 with a local CUDA build
  (`NODE_LLAMA_CPP_GPU=cuda`).
- ClawMem v0.42.0 (`89f65f1`, latest tag at the time of measurement): a fresh clone with `bun install`.
- Embeddings: `nomic-embed-text` via Ollama 0.32.6 at `localhost:11434`, which is what the vaults were embedded with.
- LLM, two configurations:
  - ClawMem's default expansion model, `qmd-query-expansion-1.7B-q4_k_m`, on llama.cpp `llama-server`
    (`d89651a`) at `127.0.0.1:8089`, using the flags from `docs/guides/inference-services.md`.
  - The LLM from our September runs, `gemma3:12b` via Ollama.
- Reranker: `qwen3-reranker-0.6B-Q8_0` (the default, already in `~/.cache/qmd/models`) on
  `llama-server --reranking` at `127.0.0.1:8090`, using the documented flags.

## Method (`scripts/time_hook.py`)

- **Vaults.** We used the 10 per-question vaults (in `ls` order) from our September `deep` run: LongMemEval_s
  haystacks of about 240 documents, embedded. Each vault also holds one `_clawmem/handoffs/…` note that
  the September run wrote. **Every call gets a fresh copy** of the vault, so no `hook_dedupe` row, rerank
  score cache or surfacing state carries over between calls. v0.42 migrates its copy on open.
- **Prompt.** The LongMemEval question, verbatim, sent as UserPromptSubmit JSON on stdin to
  `clawmem hook context-surfacing`. `CLAWMEM_HOOK_DEDUP_WINDOW_SEC=0` is set on every call.
- **Profile and budget.** `CLAWMEM_PROFILE=deep` unless the arm says `balanced`. A-MEM is off. For v0.42,
  `CLAWMEM_HOOK_BUDGET_MS` is left at its default (6000).
- **Watcher.** Each v0.42 call has `clawmem watch` running on the copy, from the same build. The script
  waits until `vec-daemon-health` reports live, then makes the call and kills the watcher. Watcher
  startup is excluded from the wall time.
- **Wall time.** Measured around the hook subprocess only, so Bun startup is included. There were three
  calls per question (30 per arm), except for the leg-timing arms (10).
- **What counts as injected.** A call is injected when `additionalContext` is non-empty. A call counts as
  evidence when that context includes a LongMemEval evidence session (`conversations/answer_*`). The
  evidence check uses the saved stdout, which exists only for pass 3.
- **Leg timing.** `patches/v037-leg-timing.diff` is applied to a *copy* of v0.37.0. It adds stderr lines
  around `expandQuery` (with the remote call split out), the in-process model load, and `store.rerank`.
  It changes no behaviour.
- **FTS experiment.** `patches/patch_fts.py` adds `CLAWMEM_EXP_FTS` to a *copy* of v0.42.0, with two
  modes: `and-nostop` (stopwords dropped, terms still ANDed) and `or` (stopwords dropped, terms ORed).
  When the variable is unset the behaviour is identical to v0.42.0 (the code adds one module-level stopword set and an env read). Both modes also drop single-character tokens, and the stopword list is ad hoc (it includes "new", "many", "much" and "since"). This is an experiment, not a proposed patch.

## Pass 5 (primary data, after crucible round 1)

`scripts/time_pass5.py`, run in this order:
1. `scripts/pass5/run_pass5.sh`: phase A, then B and its controls. Phase A died on an unhandled hook hang and is
   kept as `results/pass5-A-aborted.jsonl`; B, the controls and the FTS counts completed.
2. `scripts/pass5/run_pass5_A.sh`: phase A2, a full re-run of A with the hang handling below.
3. `scripts/pass5/run_pass5_C.sh`: phase C, added after crucible round 2. It puts every reranker configuration
   in one interleaved phase, and "no reranker" points the URL at a closed port (`:8091`).
   This is the primary source for timing.

`python3 scripts/summarize_pass5.py > results/pass5-summary.md` rebuilds every pass-5 table. It keeps statistics per phase.

The differences from the method above:
- **Interleaved arms.** For each question and round, every arm runs once, in a seeded random order.
- **Host state recorded.** Each call records the 1-minute load average and GPU utilisation.
- **Injected paths recorded.** Each call records its injected document paths and an evidence flag, so every count
  can be audited from the JSONL.
- **Phase A** stops our reranker on `:8090`. The `bin/clawmem` wrapper exports
  `CLAWMEM_RERANK_URL=${CLAWMEM_RERANK_URL:-http://localhost:8090}`, so leaving the variable unset still reaches
  whatever listens on 8090. **Phase B** restarts it with the same flags.
- **Negative controls.** `PROMPT_MODE=offtopic` asks a vault another vault's question; `gibberish` uses three
  fixed nonsense strings.
- **Handoff stripped.** `STRIP_HANDOFF=1` deactivates the vault's single `_clawmem` handoff document in the copy.
- **Hangs recorded.** A hook that doesn't exit within `HOOK_TIMEOUT` (120 s) is killed and recorded with
  `timed_out: true`.
- **Uncapped FTS counts.** `scripts/pass5/fts_hits.sh` counts full-question FTS hits with `--num 500`. The CLI
  default of 10 capped an earlier count.
- **Toy reproduction.** `repro/toy_repro.sh` is a four-note reproduction that needs none of our data. Its output on
  a clean v0.42.0 is in `repro/toy_repro.out`.

The host is shared with other GPU tenants (other users' vLLM and Ollama models). Absolute times include
that contention. Comparisons between interleaved arms are fair.

## Reproduce

`scripts/run_grid.sh`, `run_grid2.sh` and `run_grid3.sh` are the exact launchers. Run them in order on a
host with the vaults in `~/pt/clawmem-q/<qid>` and the two `llama-server`s up. `scripts/summarize.py`
rebuilds the pass 1–4 tables, and `scripts/summarize_pass5.py` rebuilds the pass-5 tables. The vaults themselves are private benchmark builds and are not published. `toy_repro.sh` is the self-contained reproduction.
