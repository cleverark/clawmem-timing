## Wall time, injection and evidence (questions are x/10; repeat calls are nearly deterministic)

| phase | prompts | arm | calls | median s | p90 s | max s | questions injected | questions w/ evidence | mean items | median load1 |
|---|---|---|---|---|---|---|---|---|---|---|
| A2 | own | v037-nolocal-norr | 30 | 3.98 | 5.40 | 6.03 | 10/10 | 10/10 | 17.6 | 3.83 |
| A2 | own | v037-norr | 30 | 9.95 | 13.10 | 120.55 | 10/10 | 10/10 | 17.9 | 3.66 |
| A2 | own | v042-nolocal-norr | 30 | 2.25 | 3.33 | 5.78 | 0/10 | 0/10 | 0.0 | 3.81 |
| A2 | own | v042-norr | 30 | 2.66 | 3.30 | 5.77 | 0/10 | 0/10 | 0.0 | 3.73 |
| B | gibberish | v037-rr | 10 | 3.35 | 4.59 | 12.29 | 10/10 | 3/10 | 13.1 | 2.95 |
| B | gibberish | v042-rr | 10 | 1.09 | 4.25 | 5.19 | 0/10 | 0/10 | 0.0 | 2.91 |
| B | gibberish | v042x-andnostop | 10 | 3.03 | 3.87 | 4.13 | 0/10 | 0/10 | 0.0 | 2.91 |
| B | gibberish | v042x-or | 10 | 2.12 | 3.73 | 4.45 | 4/10 | 0/10 | 1.3 | 2.96 |
| B | offtopic | v037-rr | 10 | 1.41 | 6.54 | 6.64 | 10/10 | 3/10 | 16.6 | 2.81 |
| B | offtopic | v042-rr | 10 | 1.09 | 3.07 | 4.56 | 0/10 | 0/10 | 0.0 | 2.78 |
| B | offtopic | v042x-andnostop | 10 | 2.15 | 3.87 | 5.14 | 1/10 | 0/10 | 0.3 | 2.79 |
| B | offtopic | v042x-or | 10 | 1.37 | 4.16 | 4.21 | 10/10 | 2/10 | 3.6 | 2.80 |
| B | own | v037-rr | 30 | 1.48 | 4.72 | 6.00 | 10/10 | 9/10 | 14.3 | 4.11 |
| B | own | v042-rr | 30 | 1.10 | 5.05 | 5.77 | 0/10 | 0/10 | 0.0 | 3.83 |
| B | own | v042x-andnostop | 30 | 1.27 | 4.09 | 5.73 | 3/10 | 3/10 | 1.1 | 3.86 |
| B | own | v042x-or | 30 | 1.31 | 4.20 | 5.34 | 10/10 | 9/10 | 2.4 | 4.17 |
| B-strip | own | v037-rr | 10 | 1.47 | 5.08 | 17.45 | 10/10 | 9/10 | 12.9 | 2.49 |
| B-strip | own | v042-rr | 10 | 1.10 | 3.50 | 4.11 | 0/10 | 0/10 | 0.0 | 2.50 |
| B-strip | own | v042x-andnostop | 10 | 1.18 | 4.12 | 4.22 | 3/10 | 3/10 | 0.9 | 2.46 |
| B-strip | own | v042x-or | 10 | 1.33 | 2.41 | 5.99 | 10/10 | 9/10 | 2.4 | 2.50 |
| C | own | v037-inproc | 30 | 11.14 | 15.62 | 120.11 | 10/10 | 10/10 | 17.3 | 2.62 |
| C | own | v037-nolocal-dead | 30 | 3.64 | 5.25 | 5.90 | 10/10 | 10/10 | 17.1 | 2.74 |
| C | own | v037-rr | 30 | 3.65 | 5.34 | 10.66 | 10/10 | 9/10 | 14.2 | 2.66 |
| C | own | v042-nolocal-dead | 30 | 2.51 | 4.22 | 5.70 | 0/10 | 0/10 | 0.0 | 2.65 |
| C | own | v042-rr | 30 | 3.29 | 4.91 | 5.31 | 0/10 | 0/10 | 0.0 | 2.62 |

## v0.37 legs (instrumented copy), own prompts, per phase

| phase | arm | calls | reranker ran | store.rerank ms min / median / max | remote expansion ms median |
|---|---|---|---|---|---|
| A2 | v037-nolocal-norr | 30 | 0/30 | — | 1940 |
| A2 | v037-norr | 30 | 29/30 | 2593 / 5308 / 6998 | 2203 |
| B | v037-rr | 30 | 30/30 | 253 / 292 / 910 | 478 |
| B-strip | v037-rr | 10 | 9/10 | 256 / 276 / 801 | 574 |
| C | v037-inproc | 30 | 28/30 | 2700 / 6192 / 12476 | 2174 |
| C | v037-nolocal-dead | 30 | 0/30 | — | 1954 |
| C | v037-rr | 30 | 29/30 | 261 / 666 / 918 | 2014 |

## Exit status (every file, including the aborted attempt)

| file | arm | rc | timed out | calls |
|---|---|---|---|---|
| pass5-A-aborted.jsonl | v037-norr | -5 | False | 15 |
| pass5-A2.jsonl | v037-norr | -5 | False | 22 |
| pass5-A2.jsonl | v037-norr | -9 | True | 1 |
| pass5-C.jsonl | v037-inproc | -5 | False | 21 |
| pass5-C.jsonl | v037-inproc | -9 | True | 1 |

All other calls exited 0. The aborted attempt's one unrecorded call was killed by the first harness's 180 s timeout (results/grid5.log).
