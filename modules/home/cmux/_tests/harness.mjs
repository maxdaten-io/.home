// Stub the cmux sidebar runtime, run worktrees.js, print entries() as a tree.
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const chain = () => new Proxy(function () {}, { get: () => () => chain(), apply: () => chain() });
const H = "/Users/jloos/Developer";
const now = Date.now() / 1000;
const W = [
  // work repo: main checkout workspace (no agent), cw worktree needing input, one working, one idle w/o agent
  { id: "1", directory: `${H}/frontrow/front-row-ai`, branch: "development", description: `cw:${H}/frontrow/front-row-ai`, tabs: [] },
  { id: "1b", title: "scratch shell", directory: `${H}/frontrow/front-row-ai`, branch: "development", tabs: [] },
  { id: "2", directory: `${H}/frontrow/front-row-ai`, description: `cw:${H}/frontrow/front-row-ai.worktrees/fix-login`, tabs: [],
    agents: [{ status: "needs_input", directory: `${H}/frontrow/front-row-ai.worktrees/fix-login`, lastActivityAt: now - 60 }] },
  { id: "3", directory: `${H}/frontrow/front-row-ai`, description: `cw:${H}/frontrow/front-row-ai.worktrees/perf`, tabs: [],
    agents: [{ status: "working", directory: `${H}/frontrow/front-row-ai.worktrees/perf`, lastActivityAt: now - 30 }] },
  { id: "4", directory: `${H}/frontrow/front-row-ai`, description: `cw:${H}/frontrow/front-row-ai.worktrees/old`, latestAt: now - 9000, tabs: [] },
  // private repo: no root workspace, only a claude -w worktree; agent in main checkout of another repo
  { id: "5", directory: `${H}/.home`, tabs: [], agents: [{ status: "idle", directory: `${H}/.home/.claude/worktrees/sidebar`, lastActivityAt: now - 600 }] },
  { id: "6", directory: `${H}/MaxDaten/blog`, branch: "main", tabs: [], agents: [{ status: "working", directory: `${H}/MaxDaten/blog`, lastActivityAt: now - 5 }] },
  // non-git plain shell: must not appear
  { id: "7", directory: "/Users/jloos", tabs: [] },
  { id: "9", title: "cmux sidebar layout", directory: `${H}/.home`, tabs: [], agents: [{ status: "working", directory: `${H}/.home`, lastActivityAt: now - 3 }] },
  { id: "10", title: "Cw.sh rewrite", directory: `${H}/.home`, tabs: [], agents: [{ status: "idle", directory: `${H}/.home`, lastActivityAt: now - 18000 }] },
  { id: "8", pinned: true, title: "triage", directory: `${H}/frontrow/x`, tabs: [] },
];
let entries;
const g = {
  data: { workspaces: () => W },
  signal: (v) => { let x = v; return [() => x, (n) => (x = n)]; },
  computed: (f) => { entries = f; return f; },
  sidebar: () => {}, cmux: () => {}, openURL: () => {}, clipboard: {},
};
for (const n of ["VStack","HStack","Text","Image","Circle","Spacer","ForEach","Button"]) g[n] = chain;
new Function(...Object.keys(g), src)(...Object.values(g));
const ind = { section: 0, pinned: 1, repo: 1, row: 2, sub: 2, group: 3, more: 4 };
for (const e of entries()) {
  const pad = "  ".repeat(ind[e.kind] + (e.kind === "row" && e.nested ? 2 : 0));
  const t = e.kind === "section" ? e.label : e.kind === "repo" ? e.root.split("/").pop()
    : e.kind === "row" ? `${(e.row.session ? e.row.w.title : e.row.path.split("/").pop())}${e.row.path === e.row.root ? " [main]" : ""} status=${e.row.agent?.status ?? "-"} ws=${e.row.w?.id ?? "none"}`
    : e.kind === "group" ? `${e.word} (${e.count})` : e.kind === "pinned" ? "📌 " + e.w.title : e.label ?? e.hidden;
  console.log(pad + t);
}
