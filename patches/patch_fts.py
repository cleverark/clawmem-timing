p = "src/store.ts"; s = open(p).read()
a = """function buildFTS5Query(query: string): string | null {
  const terms = tokenizeForFTS5(query);
"""
assert s.count(a) == 1
stop = ("a an and are as at be but by can could did do does for from had has have how i if in into is it its me my of on or our so "
        "than that the their them then there these they this to was we were what when where which who why will with would you your "
        "about after again all also am any been before being both each few further here just more most much new now only other own "
        "same should some such too under until very many since")
s = s.replace(a, """// EXPERIMENT (not upstream): CLAWMEM_EXP_FTS=or | and-nostop
const __EXP_STOP = new Set("%s".split(" "));
function buildFTS5Query(query: string): string | null {
  const __mode = process.env.CLAWMEM_EXP_FTS;
  if (__mode === "or" || __mode === "and-nostop") {
    const t = tokenizeForFTS5(query).filter(x => !__EXP_STOP.has(x) && x.length > 1);
    if (t.length === 0) return null;
    return t.map(x => `"${x}"*`).join(__mode === "or" ? " OR " : " AND ");
  }
  const terms = tokenizeForFTS5(query);
""" % stop)
open(p, "w").write(s)
print("patched")
