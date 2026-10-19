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
];
let bad = 0;
for (const [w, a, want] of cases) {
  const got = sessionName(w, a);
  console.log(got === want ? "ok  " : "FAIL", JSON.stringify(got), "want", JSON.stringify(want));
  bad += got !== want;
}
process.exit(bad);
