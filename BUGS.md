# Open low-severity notes (after crucible round 4; item closed under the tooling tier)

- r4-L5: pass-5 v0.42 calls aren't traced individually. 13 of the 160 ran ≥5 s, and 6 of those logged a remote-LLM
  TimeoutError. That they returned empty context is measured; that the cause was admission is inferred from the
  pass-4 traces. The drafts say "in separate traced runs".
- r4-L9: the instrumented v0.37 copy on the host also carries our local, unset-by-default CLAWMEM_HOOK_TIMEOUT_MS
  edit in src/openclaw/shell.ts, left over from PR yoloshii/ClawMem#27 work. It has no effect, because hooks are run by hand and
  cited lines come from the clean v0.37.0 tag.
- r4-M1 detail: the phase-B 1.10 s median mixes idle-GPU calls (15/30, median 1.01 s) and loaded calls
  (15/30, median 3.82 s).
- PR yoloshii/ClawMem#30's opt-in fallback was verified by the Sonnet readers (gh). Codex couldn't reach GitHub from its sandbox.
