// Extract GLYPH + sessionName from the sidebar source and check real titles.
import fs from "node:fs";
const src = fs.readFileSync(process.argv[2], "utf8");
const body = src.slice(src.indexOf("const GLYPH"), src.indexOf("// --- model"));
const sessionName = new Function(body + "; return sessionName;")();
const cases = [
  // this session, shell tab focused (the screenshot)
  [{ title: "claude attach de2bcc ~/D/.home", tabs: [{ id: "A", title: "◐ cmux sidebar layout" }, { id: "B", title: "~/D/.home" }] }, { panelId: "B" }, "cmux sidebar layout"],
  [{ title: "✳ frai", tabs: [{ id: "A", title: "✳ frai" }] }, { panelId: "A" }, "frai"],
  [{ title: "✳ codebase architecture refactor", tabs: [] }, null, "codebase architecture refactor"],
  [{ title: "Cw.sh rewrite language choice", tabs: [{ id: "A", title: "~/D/.home" }] }, null, "Cw.sh rewrite language choice"],
  [{ title: "~/D/.home", tabs: [{ id: "A", title: "/Users/jloos" }] }, null, "~/D/.home"],
  // live claude whose tab title has no status glyph (2026-10 screenshot):
  // the agent's own tab still names it; the workspace title is just the repo
  [{ title: "front-row-ai", tabs: [{ id: "A", title: "Learning from the /pr skill" }] }, { panelId: "A" }, "Learning from the /pr skill"],
  // ...but an own tab that reads as a shell does not
  [{ title: "front-row-ai", tabs: [{ id: "A", title: "~/D/f/front-row-ai" }] }, { panelId: "A" }, "front-row-ai"],
  [{ title: "x", tabs: [{ id: "A", title: "claude attach de2bcc ~/D/.home" }] }, { panelId: "A" }, "x"],
  // a glyph-less title on some *other* tab is not trusted
  [{ title: "front-row-ai", tabs: [{ id: "A", title: "~/D/f/front-row-ai" }, { id: "B", title: "vim notes.md" }] }, { panelId: "A" }, "front-row-ai"],
];
let bad = 0;
for (const [w, a, want] of cases) {
  const got = sessionName(w, a);
  console.log(got === want ? "ok  " : "FAIL", JSON.stringify(got), "want", JSON.stringify(want));
  bad += got !== want;
}
process.exit(bad);
