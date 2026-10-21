// Run collectRows with a recording cmux stub: which workspaces get stamped, how often.
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const calls = [];
const g = { data: { workspaces: () => [] }, signal: (v) => [() => v, () => {}], computed: (f) => f, sidebar: () => {}, cmux: (m, p) => calls.push([m, p]), openURL: () => {}, clipboard: {} };
const body = src.slice(0, src.indexOf("// Collapsed sections")) + "; return collectRows;";
const collectRows = new Function(...Object.keys(g), body)(...Object.values(g));
const R = "/r/repo", W = R + "/.claude/worktrees/brave-otter";
const ws = [
  { id: "bare", directory: R, tabs: [], agents: [{ status: "working", directory: W, lastActivityAt: 1 }] },              // claude -w, unstamped -> stamp
  { id: "cw", directory: R, description: "cw:" + W + "x", tabs: [], agents: [{ status: "idle", directory: W + "x" }] }, // already stamped -> skip
  { id: "user", directory: R, description: "my notes", tabs: [], agents: [{ status: "idle", directory: W + "y" }] },   // user description -> skip
  { id: "root", directory: R, tabs: [], agents: [{ status: "idle", directory: R }] },                                  // root session -> skip
];
collectRows(ws); collectRows(ws); collectRows(ws); // three refresh ticks
console.log(JSON.stringify(calls));
const ok = calls.length === 1 && calls[0][1].workspace_id === "bare" && calls[0][1].description === "cw:" + W && calls[0][1].action === "set_description";
console.log(ok ? "ok   one stamp, right workspace and path, no repeats" : "FAIL"); if (!ok) process.exit(1);
// Stamped while its agent was in the worktree, agent since back at the root
// (worktree exited/removed): still one session, one row.
const left = [{ id: "left", directory: R, description: "cw:" + W, tabs: [], agents: [{ status: "idle", directory: R }] }];
const rows = collectRows(left).map((r) => r.path);
console.log(JSON.stringify(rows));
const one = rows.length === 1 && rows[0] === R;
console.log(one ? "ok   left worktree: one row, at the root" : "FAIL"); if (!one) process.exit(1);
// Workflow subagents run in wf_* worktrees and their hook events move the
// parent's reported directory: the session stays at the root, unstamped, even
// over a stamp an earlier tick wrote from such an event.
calls.length = 0;
const wf = [
  { id: "wf", directory: R, tabs: [], agents: [{ status: "working", directory: R + "/.claude/worktrees/wf_ddddbc08-1d4-6" }] },
  { id: "wf-stamped", directory: R, description: "cw:" + R + "/.claude/worktrees/wf_ddddbc08-1d4-1", tabs: [], agents: [{ status: "working", directory: R + "/.claude/worktrees/wf_ddddbc08-1d4-2" }] },
];
const wfRows = collectRows(wf).map((r) => r.path + (r.session ? " session" : ""));
console.log(JSON.stringify({ wfRows, calls }));
const sub = JSON.stringify(wfRows) === JSON.stringify([R + " session", R + " session"]) && calls.length === 0;
console.log(sub ? "ok   wf_ subagent dirs: root session rows, no stamp" : "FAIL"); process.exit(sub ? 0 : 1);
