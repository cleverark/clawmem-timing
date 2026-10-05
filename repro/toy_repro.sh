#!/usr/bin/env bash
# Minimal reproduction of the context-surfacing abstain on a 4-note vault. No benchmark data needed.
#
# Usage: CLAWMEM=/path/to/ClawMem/bin/clawmem [CLAWMEM_EMBED_URL=... CLAWMEM_EMBED_MODEL=...] ./toy_repro.sh
#
# Part 1 (keyword search) needs no models: the notes are indexed WITHOUT embeddings first.
# Part 2 (the hook) needs an embedding endpoint (CLAWMEM_EMBED_URL; the wrapper default is :8088). The abstain does
# NOT depend on a reranker or an LLM endpoint: `balanced` uses neither, and `deep` degrades within its budget.
# CLAWMEM_NO_LOCAL_MODELS defaults to true here so a stock install never auto-downloads models.
# Needs: bash, python3, sqlite3. The output in toy_repro.out came from v0.42.0 (89f65f1) with nomic-embed-text via
# Ollama, qmd-query-expansion-1.7B on :8089 and qwen3-reranker-0.6B on :8090.
# toy_repro-embed-only.out came from the same script with CLAWMEM_LLM_URL=http://127.0.0.1:8092 and
# CLAWMEM_RERANK_URL=http://127.0.0.1:8091, two closed ports, and the same embedding endpoint.
# Prerequisite: `bun install` in the ClawMem checkout.
set -euo pipefail
CLAWMEM=${CLAWMEM:?set CLAWMEM to the clawmem wrapper (…/ClawMem/bin/clawmem)}
for c in python3 sqlite3; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
export CLAWMEM_NO_LOCAL_MODELS=${CLAWMEM_NO_LOCAL_MODELS:-true}
export CLAWMEM_ENABLE_AMEM=${CLAWMEM_ENABLE_AMEM:-false}   # no LLM enrichment during indexing

W=$(mktemp -d); WPID=""
trap '[ -n "$WPID" ] && kill "$WPID" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$W/notes" "$W/config"
export INDEX_PATH="$W/index.sqlite" CLAWMEM_CONFIG_DIR="$W/config" CLAWMEM_HOOK_DEDUP_WINDOW_SEC=0

cat > "$W/notes/postcards.md" <<'EOF'
# Postcards
I started collecting postcards again last spring. Since then I've added 17 new postcards to my collection,
mostly from flea markets and two from a swap with a friend in Lisbon.
EOF
cat > "$W/notes/sourdough.md" <<'EOF'
# Sourdough
My starter is finally active. I feed it twice a day with rye and bake on Saturdays.
EOF
cat > "$W/notes/bike.md" <<'EOF'
# Bike maintenance
Replaced the chain and the rear brake pads. The gears still skip on the smallest cog.
EOF
cat > "$W/notes/garden.md" <<'EOF'
# Garden
The tomatoes are doing well this year; the basil bolted early in the heat.
EOF

"$CLAWMEM" collection add "$W/notes" --name toy >/dev/null
"$CLAWMEM" update >/dev/null          # index only; no embeddings yet

Q="How many new postcards have I added to my collection since I started collecting again?"
hits () { local out; out=$("$CLAWMEM" search --num 50 "$1") || { echo "search failed" >&2; exit 1; }; grep -c 'postcards.md' <<< "$out" || true; }
echo "== Part 1: keyword search (no models used)"
full_hits=$(hits "$Q") || exit 1
kw_hits=$(hits "postcards collection") || exit 1
echo "full question:          $full_hits hit(s) on postcards.md"
echo "'postcards collection': $kw_hits hit(s) on postcards.md"

echo "== Part 2: context-surfacing hook, CLAWMEM_SURFACING_TRACE=1, watcher running"
"$CLAWMEM" embed >"$W/embed.log" 2>&1 || { cat "$W/embed.log" >&2; echo "embedding failed: is CLAWMEM_EMBED_URL (${CLAWMEM_EMBED_URL:-wrapper default :8088}) up?" >&2; exit 1; }
"$CLAWMEM" watch >/dev/null 2>&1 & WPID=$!
live=no; for i in $(seq 1 40); do "$CLAWMEM" vec-daemon-health >/dev/null 2>&1 && { live=yes; break; }; sleep 0.5; done
[ "$live" = yes ] || echo "WARNING: vector daemon never reported live; Part 2 runs without it" >&2
run_hook () {
  printf '{"session_id":"toy-%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$RANDOM" "$1" \
    | CLAWMEM_SURFACING_TRACE=1 "$CLAWMEM" hook context-surfacing \
    | python3 -c 'import json,sys; c=json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]; print("  injected postcards.md:", "postcards.md" in c)'
  sqlite3 "$INDEX_PATH" "select trace_json from surfacing_diagnostics order by id desc limit 1" | python3 -c '
import json,sys; t=json.load(sys.stdin); a=t.get("admission") or {}
lanes=sorted({l["lane"] for l in (t.get("fusion") or {}).get("lanes",[]) if isinstance(l,dict) and "lane" in l})
print("  outcome:", t["outcome"], "/", t.get("emptyReason"), "| abstainReason:", a.get("abstainReason"), "| keywordAgreed:", a.get("keywordAgreed"), "| lanes:", lanes)'
}
for P in "$Q" "my postcards collection since I started again"; do
  for profile in balanced deep; do
    echo "-- [$profile] $P"; CLAWMEM_PROFILE=$profile run_hook "$P"
  done
done
