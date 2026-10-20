// entries() over one repo with 6 waiting and 6 idle worktree sessions: a
// session that needs you is never folded into "+N older"; idle still caps.
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const chain = () => new Proxy(function () {}, { get: () => () => chain(), apply: () => chain() });
const R = "/Users/jloos/Developer/MaxDaten/repo";
const W = [];
for (const [status, n] of [["needs_input", 6], ["idle", 6]])
  for (let i = 0; i < n; i++) {
    const path = `${R}/.claude/worktrees/${status}-${i}`;
    W.push({ id: path, directory: R, description: "cw:" + path, tabs: [], agents: [{ status, directory: path, lastActivityAt: i }] });
  }
let entries;
const g = {
  data: { workspaces: () => W },
  signal: (v) => { let x = v; return [() => x, (n) => (x = n)]; },
  computed: (f) => { entries = f; return f; },
  sidebar: () => {}, cmux: () => {}, openURL: () => {}, clipboard: {},
};
for (const n of ["VStack","HStack","Text","Image","Circle","Capsule","Spacer","ForEach","Button"]) g[n] = chain;
new Function(...Object.keys(g), src)(...Object.values(g));
const es = entries();
const rows = (s) => es.filter((e) => e.kind === "row" && e.row.agent?.status === s).length;
const more = es.filter((e) => e.kind === "more").map((e) => e.listKey.split(":").pop() + "+" + e.hidden);
const got = JSON.stringify({ needs: rows("needs_input"), idle: rows("idle"), more });
const want = JSON.stringify({ needs: 6, idle: 5, more: ["idle+1"] });
console.log(got === want ? "ok  " : "FAIL", got, "want", want); process.exit(got === want ? 0 : 1);
