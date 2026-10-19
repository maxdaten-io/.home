import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const body = src.slice(src.indexOf("const allFolded"), src.indexOf("// Two sibling tap targets"));
const collapsed = new Set(); let t = 0;
const { foldRepos } = new Function("collapsed", "tick", "setTick", body + "; return { foldRepos };")(collapsed, () => t, (v) => (t = v));
const keys = ["r:/a", "r:/b", "r:/c"];
const check = (name, want) => { const got = keys.filter((k) => collapsed.has(k)).join(","); console.log(got === want ? "ok  " : "FAIL", name, JSON.stringify(got)); if (got !== want) process.exitCode = 1; };
collapsed.add("s:WORK!"); // unrelated keys must survive
foldRepos(keys); check("fold all", "r:/a,r:/b,r:/c");
foldRepos(keys); check("all folded -> unfold all", "");
collapsed.add("r:/b"); foldRepos(keys); check("mixed -> fold rest", "r:/a,r:/b,r:/c");
console.log(collapsed.has("s:WORK!") ? "ok   section key untouched" : "FAIL section key touched");
if (!collapsed.has("s:WORK!")) process.exitCode = 1;
