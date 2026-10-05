# Results

The primary data is **pass 5**, run after crucible rounds 1 and 2 (`results/pass5-*.jsonl`,
`scripts/time_pass5.py`, `scripts/pass5/`). `scripts/summarize_pass5.py` rebuilds every pass-5 table into
`results/pass5-summary.md`. Passes 1–4 are kept below as history, but two problems found in review invalidate parts of
them (see "Passes 1–4" at the end).

Pass 5 setup:
- **Interleaving.** For each question and each round, every arm runs once, in a seeded random order.
- **Host.** It is shared, with other tenants' vLLM and Ollama models on the same GPU. Load and GPU
  utilisation are recorded per call. Absolute times are inflated by that contention. Comparisons
  between interleaved arms are fair.
- **No-reranker arms.** The `bin/clawmem` wrapper defaults `CLAWMEM_RERANK_URL` to `:8090`. These arms
  either stop the server (A2) or point the URL explicitly at a closed port (C).
- **Data.** 10 questions, 3 calls each, fresh vault copy per call. Every record carries its injected document
  paths. "Evidence" means a LongMemEval evidence session (`conversations/answer_*`). Rates are given per
  question (x/10), because repeat calls are nearly deterministic.
- **Pipeline.** Deep profile, default 6 s budget, `nomic-embed-text` via Ollama. The LLM is
  `qmd-query-expansion-1.7B` on `llama-server`. v0.37 calls use the leg-instrumented copy
  (`patches/v037-leg-timing.diff`, stderr lines only). `clawmem watch` runs for v0.42 calls only.
- **Phases.** C puts every reranker configuration in one interleaved phase and is primary for timing. A2 has the reranker stopped. B has it running, plus the controls. B-strip is B with the handoff note removed.

## 1. The two wall times asked for in yoloshii/ClawMem#28 (v0.42.0)

All of these are **phase C**: every reranker configuration runs in one interleaved phase. "No reranker
reachable" means `CLAWMEM_RERANK_URL` points explicitly at a closed port (`:8091`). The host was shared, with
another tenant's Ollama model generating (GPU around 95%). `clawmem watch` was running for every call.

| v0.42.0, deep | calls | median | p90 | max | exit 0 | injected |
|---|---|---|---|---|---|---|
| `CLAWMEM_RERANK_URL` → reranker server | 30 | 3.29 s | 4.91 s | 5.31 s | 30/30 | 0/30 |
| `CLAWMEM_NO_LOCAL_MODELS=true`, no reranker reachable | 30 | 2.51 s | 4.22 s | 5.70 s | 30/30 | 0/30 |

- Phases A2 and B ran the same two configurations, each on its own, not interleaved with each other.
  They give 1.10 s (B, server) and 2.25 s (A2, `NO_LOCAL`), with max 5.77 s and 5.78 s.
- Across all 160 unmodified v0.42.0 calls in pass 5 that used the question as the prompt, the maximum was 5.78 s and every call exited 0.
  So the timeout did not recur in these runs.
- **Every one of these calls returned empty context.** The pass-4 traces (section 3) show that as admission
  abstaining. So these are not times for calls that went on to inject.
- p90 is nearest-rank.
- These pass-5 v0.42 calls record no leg timings. Whether rerank ran inside them isn't measured here.
  The pass-4 traces show rerank attempted on 10 of 10 `deep` calls with the reranker server up.
- With a deadline present, v0.42 never starts in-process rerank. The local fallback requires
  `deadline === undefined` (`store.ts:5704`), so the `NO_LOCAL` row reranks nothing whether or not the flag
  is set.

## 2. Where the 25–39 s went at v0.37.0

**Our September config (gemma3:12b as the LLM).** These are pass-3 leg timings, 10 instrumented calls per arm,
on a contended host. The arms ran in sequence, with the wrapper's default `:8090` reranker running in all of
them.

| arm (pass 3) | remote expansion call | expansion variants returned | reranker ran |
|---|---|---|---|
| rerank URL unset (wrapper default `:8090` up) | 13.6–57.0 s | 1 | 0/10 |
| explicit rerank URL `:8090` | 8.3–41.8 s | 1 | 0/10 |
| `NO_LOCAL_MODELS=true` (wrapper default `:8090` up) | 8.2–43.0 s | 1 | 0/10 |

- At v0.37.0, `expandQueryRemote` calls `generateRemote(prompt, 500, 0.7)` with no abort signal
  (`llm.ts:1505`). Nothing inside the hook process bounds the call.
- The only limits were outside the call: the OpenClaw plugin's `execFile` kill (10 s, `shell.ts:67`) and the
  host hook timeout. The `DEFAULT_TIMEOUT` constant is at `shell.ts:67` and the `execFile` timeout at `:91`.
- **Our yoloshii/ClawMem#28 report was wrong** to say the call was bounded by `AbortSignal.timeout(opts.timeoutMs ?? 10_000)`.
  That abort belongs to `probeChatCompletionsShape` (`llm.ts:1063`), a setup probe.
- The reranker never ran on these calls. Expansion returned after at least 8 s, so the `Date.now() -
  startTime < 6000` gate before rerank (`context-surfacing.ts:343`) was already false.
- The arms ran in sequence on a contended host, so the differences between them are uncontrolled. The
  instrumentation shows only that the reranker cannot be the cause.
- This re-run is consistent with the original 25–39 s being the unbounded expansion call. It's a
  re-creation of the September config, not a trace of the September calls themselves.

**With ClawMem's default expansion model** (phase C, all three arms interleaved, instrumented v0.37.0 copy):

| v0.37.0 arm | calls | median wall | exit 0 | completed `store.rerank` calls | `store.rerank` call (init + inference), completed calls |
|---|---|---|---|---|---|
| reranker server | 30 | 3.65 s | 30/30 | 29/30 | 0.26–0.92 s (median 0.67) |
| **in-process reranker** (URL → closed port, local allowed) | 30 | **11.14 s** | **8/30** | 28/30 | **2.7–12.5 s (median 6.2)** |
| `NO_LOCAL_MODELS=true`, no reranker reachable | 30 | 3.64 s | 30/30 | 0/30 | — |

- **The in-process reranker is costly.** On this CUDA build, the in-process `store.rerank` call
  (initialisation plus inference, not separated) takes 6.2 s median against 0.67 s via the server, in the
  same rounds. That supports the maintainer's view that loading it in-process on every prompt is the wrong
  deployment. It just wasn't what made our September calls slow.
- **The in-process calls usually crashed after writing their output.** In phase C, 21 of 30 in-process calls
  finished rerank, wrote their output, and were then killed by signal 5 (SIGTRAP). All 21 logs show
  `panic(main thread): Segmentation fault at address …`. One more call never exited and was killed at 120 s.
  - Phase A2 gave 22 crashes plus 1 hang. Its logs show 22 segfaults, and the hang printed
    `NAPI FATAL ERROR ... napi_create_object`.
  - The aborted first attempt at phase A gave 15 crashes plus 1 hang at 180 s.
  - The logs are in `results/crash-logs/`: a full example of each panic type, plus the first panic line from
    every call.
  - No other arm crashed (`results/pass5-summary.md`, exit-status table).
  - At v0.37, the OpenClaw plugin drops stdout whenever the hook errors (`shell.ts:96-103`), so those calls'
    context would not have reached the agent.
  - The combination was Bun 1.2.23, node-llama-cpp 3.15.1 and a local CUDA build. v0.42 wants node-llama-cpp
    ^3.20.0, and the maintainer uses Bun 1.3.14. We haven't isolated the cause. v0.42 never takes this path
    when a deadline is set.
- The median walls include the crashed calls. They measure time to exit, and the output was written before
  the crash.

## 3. v0.42 relevance admission abstains on natural-language questions

**Real questions** (pass 5 phase B, reranker running, interleaved):

| arm | calls | injected (questions) | evidence (questions) | mean items injected |
|---|---|---|---|---|
| v0.37.0 | 30 | 10/10 | 9/10 | 14.3 |
| v0.42.0 as shipped | 30 | 0/10 | 0/10 | 0 |
| v0.42.0 + FTS without stopwords, AND (experiment) | 30 | 3/10 | 3/10 | 1.1 |
| v0.42.0 + FTS without stopwords, OR (experiment) | 30 | 10/10 | 9/10 | 2.4 |

**Negative controls**, one call per vault. An off-topic prompt is another vault's question, so its evidence
isn't present. A gibberish prompt is one of three fixed nonsense strings.

| arm | off-topic: injected | gibberish: injected |
|---|---|---|
| v0.37.0 | 10/10 | 10/10 |
| v0.42.0 as shipped | 0/10 | 0/10 |
| v0.42.0 + AND, no stopwords | 1/10 | 0/10 |
| v0.42.0 + OR, no stopwords | 10/10 | 4/10 |

**Evidence needs a baseline.** v0.37.0's injected context included one of *this vault's* evidence sessions on
3/10 off-topic and 3/10 gibberish prompts, where none of them is relevant. So the "evidence" column measures
presence, not precision, and the off-topic and gibberish rows are the precision check.

**`balanced`** is the default profile. In pass 3, v0.42.0 injected 0 of 30 calls and v0.37.0 injected 30 of 30.
All 10 traced `balanced` calls end `degenerate-basis` (`results/traces-summary.txt`).

**Handoff note removed** (pass 5 `B-strip`, one call per vault). This made no difference: v0.42.0 injected 0/10,
the OR variant injected 10/10 with evidence on 9/10, and the AND variant injected 3/10.

**Full-question FTS hits** (`results/pass5-fts-hits.txt`, `--num 500`):
- As shipped: 0 on all 10 vaults, on both v0.37.0 and v0.42.0.
- No stopwords, AND: 0–6, non-zero on 5 of 10.
- No stopwords, OR: 29–253. The OR query matched every document in one 253-document vault.

**Mechanism.** These are pass-4 traces, one call per question (`results/traces-summary.txt`).
- All 30 traced calls end `admission-degenerate` / `degenerate-basis` with `keywordAgreed: 0`:
  10 `deep` with qmd, 10 `deep` with gemma, and 10 `balanced`.
- At `deep` with qmd the lanes were `vector`, `expansion-vec` and `expansion-lex`, with no `fts-*` lane.
- The reranker scored an evidence session at 0.99 or higher on 6 of 10 questions, and the hook rejected it.
  On the other 4 the evidence scored low (0.0001–0.52), so abstaining there is arguably correct.
- `balanced` has no deep escalation (`deepEscalation: false`), so it never reranks. Its abstentions come from the
  vector lane alone.
- `buildFTS5Query` ANDs every token as a prefix match (`"t"*`), including stopwords.
- `relevanceAdmission` abstains when no band-0 candidate carries a `KEYWORD_CLASS_LANES` lane
  (`fts-fallback`, `fts-supplement`, `file-aware`, `secondary-vault`). `expansion-lex` and rerank scores
  don't count toward agreement.

**Toy reproduction.** `repro/toy_repro.sh` builds a four-document vault and runs on a clean v0.42.0 checkout.
Its output is in `repro/toy_repro.out`.
- The full question gets 0 FTS hits and abstains as `degenerate-basis` at both `balanced` and `deep`.
- A prompt whose words all occur in the note gets `fts-supplement` agreement and injects.

**What this does and doesn't show.**
- Neither naive variant is a fix. OR brings back recall but gives up abstention on off-topic prompts, which
  is exactly what the gate exists to stop (Addendum 2/6). AND without stopwords keeps abstention but
  recovers only 3 of 10 questions.
- The agreement signal probably needs something between the two.
- Caveats: 10 LongMemEval_s questions; ~240-document vaults built from benchmark haystacks; nomic
  embeddings, not embeddinggemma; vaults written by v0.37 and migrated on open; one shared host.
- Related: upstream PR yoloshii/ClawMem#30 adds an opt-in any-term fallback to `searchFTS` for `search`, `memory_retrieve`
  and `query`. It doesn't touch the hook's lanes.

## Passes 1–4 (history)

These passes produced `results/v0*.jsonl`, `legs-*`, `trace-*` and `v042x-*`. Two problems were found in
crucible round 1:
- **No real "no-server" arms.** The wrapper's default rerank URL meant every "local" and "nolocal" arm
  used our running reranker. Those arms didn't measure what their names say.
- **Uncontrolled host contention.** The arms ran sequentially, on a GPU shared with other tenants, while
  load drifted. The 3.72 s and 3.95 s figures from pass 1 are mostly that, and the same config ran at
  1.00 s in pass 4.

Still valid from passes 1–4:
- the gemma expansion leg timings in section 2;
- the pass-4 traces;
- the v0.37 vs v0.42 `balanced` injection counts. These don't depend on timing or on which reranker answered.
