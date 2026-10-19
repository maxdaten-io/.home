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
console.log(ok ? "ok   one stamp, right workspace and path, no repeats" : "FAIL"); process.exit(ok ? 0 : 1);
