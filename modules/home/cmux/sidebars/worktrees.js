// worktrees: WORK (~/Developer/frontrow, same rule the claude wrapper uses to
// pick the work account) and PRIVATE, each collapsible:
//
//   WORK
//     <repo>
//       main checkout            the repo-root workspace (and its agent, if any)
//       claude sessions
//         needs input / working / idle   collapsible; named worktrees, newest first
//
// Pinned workspaces (the `claude agents` triage views) sit on top of their
// section. Pairs with `cw` (../cw.sh). Agent-centric layout after cmux's
// panel-subagents example.
//
// A row is keyed by agents[].directory, not w.directory/w.branch: those follow
// the *focused* pane, and with `claude -w` the claude pane's shell stays in the
// repo root while claude itself runs in the worktree. `cw new` stamps its
// workspace's description with "cw:<worktree>", which is how such a workspace
// is told apart from the main checkout before (and after) its agent runs.
//
// Edits hot-reload: this file is symlinked out of the Nix store on purpose.

const WORK = "/Developer/frontrow/";
const PER_GROUP = 5;
const STATUS = {
  needs_input: { color: "#E8912D", rank: 0, word: "needs input" },
  working: { color: "#4C9EEB", rank: 1, word: "working" },
  idle: { color: "#8E8E93", rank: 2, word: "" },
};
const GROUPS = [
  ["needs_input", "needs input"],
  ["working", "working"],
  ["idle", "idle"],
];
const rankOf = (a) => STATUS[a?.status]?.rank ?? 9; // no agent ranks last
const groupOf = (r) => (r.agent?.status === "needs_input" || r.agent?.status === "working" ? r.agent.status : "idle");
const stampOf = (w) => (w.description?.startsWith("cw:") ? w.description.slice(3) : null);
const isGit = (w) => !!(w.branch || (w.tabs ?? []).some((t) => t.branch));

// data.clock() is documented but undefined in the JS runtime (TypeError seen
// live); rows re-render on the data tick anyway.
const nowSecs = () => data.clock?.()?.epoch ?? Date.now() / 1000;
const secs = (t) => (t > 1e12 ? t / 1000 : t); // ms vs s isn't documented

function fmtAge(s) {
  const m = Math.max(0, Math.floor(s / 60));
  if (m < 60) return m + "m";
  const h = Math.floor(m / 60);
  return h < 24 ? h + "h" : Math.floor(h / 24) + "d";
}

// The sidebar can't run git, so the main checkout comes from the path alone:
// <root>/.claude/worktrees/<n> (claude default) or <root>.worktrees/<n>
// (front-row-ai's WorktreeCreate hook). Anything else IS a main checkout —
// no prefix folding: gitops/onboarding/mealieservice is its own repo.
function rootOf(path) {
  const m = path.match(/^(.*)\/\.claude\/worktrees\/[^/]+/) ?? path.match(/^(.*)\.worktrees\/[^/]+/);
  return m ? m[1] : path;
}
const base = (p) => p.split("/").filter(Boolean).pop() ?? "?";

// The agent's own tab knows the last prompt typed into *it*; harness
// injections (`<task-notification>…`) identify nothing, skip them.
function promptOf(w, a) {
  if (!w) return "";
  const tab = a && (w.tabs ?? []).find((t) => t.id === a.panelId);
  return [a?.title, tab?.latestPrompt, w.latestPrompt].find((p) => p && !p.trimStart().startsWith("<")) ?? "";
}

// --- model ---------------------------------------------------------------------
// One row per path. Sources, in order: live agents; `cw new` workspaces whose
// agent isn't (or no longer) running; plain git workspaces (main checkouts, or
// a worktree opened by hand). Several hits on one path: the most urgent (then
// most recent) one represents it, `others` counts the extra agents.
function collectRows(ws) {
  const byPath = new Map();
  const put = (path, w, agent, at) => {
    const prev = byPath.get(path);
    const better = !prev || rankOf(agent) < rankOf(prev.agent) || (rankOf(agent) === rankOf(prev.agent) && at > prev.at);
    const tab = (w.tabs ?? []).find((t) => t.directory === path && t.branch);
    const row = better ? { path, root: rootOf(path), w, agent, at, tab, others: 0 } : prev;
    row.at = Math.max(at, prev?.at ?? 0);
    row.others = (prev?.others ?? 0) + (prev?.agent && agent ? 1 : 0);
    byPath.set(path, row);
  };
  for (const w of ws) {
    if (w.pinned) continue; // triage views render separately
    for (const a of w.agents ?? []) {
      if (a.status === "ended") continue;
      const path = a.directory ?? stampOf(w) ?? w.directory ?? "";
      if (path) put(path, w, a, secs(a.lastActivityAt ?? a.sinceEpoch ?? 0));
    }
  }
  for (const w of ws) {
    if (w.pinned) continue;
    const path = stampOf(w) ?? (isGit(w) ? w.directory : null);
    if (path && !byPath.has(path)) put(path, w, null, secs(w.latestAt ?? 0));
  }
  return [...byPath.values()];
}

// Collapsed sections/repos/groups and expanded "+N older" lists, local to this view.
const collapsed = new Set();
const expanded = new Set();
const [tick, setTick] = signal(0);
const flip = (set, key) => {
  if (set.has(key)) set.delete(key);
  else set.add(key);
  setTick(tick() + 1);
};

const entries = computed(() => {
  tick();
  const ws = data.workspaces() ?? [];
  const rows = collectRows(ws);
  const out = [];
  for (const [label, work] of [["WORK", true], ["PRIVATE", false]]) {
    const inSection = (path) => path.includes(WORK) === work;
    const pinned = ws.filter((w) => w.pinned && inSection(w.directory ?? ""));
    const repos = new Map();
    for (const r of rows.filter((r) => inSection(r.root))) {
      if (!repos.has(r.root)) repos.set(r.root, []);
      repos.get(r.root).push(r);
    }
    if (!pinned.length && !repos.size) continue;

    const secKey = "s:" + label;
    const dots = (rs) => rs.filter((r) => r.agent).map((r) => r.agent.status);
    out.push({ kind: "section", key: secKey, label, dots: dots([...repos.values()].flat()) });
    if (collapsed.has(secKey)) continue;

    for (const w of pinned) out.push({ kind: "pinned", key: "p:" + w.id, w });

    const ordered = [...repos.entries()]
      .map(([root, rs]) => [root, rs.sort((x, y) => y.at - x.at)])
      .sort((x, y) => y[1][0].at - x[1][0].at);
    for (const [root, rs] of ordered) {
      const repoKey = "r:" + root;
      out.push({ kind: "repo", key: repoKey, root, dots: dots(rs) });
      if (collapsed.has(repoKey)) continue;

      // No workspace at the root: still listed, dimmed, so the repo has an anchor.
      const main = rs.find((r) => r.path === root) ?? { path: root, root, w: null, agent: null, at: 0, others: 0 };
      out.push({ kind: "row", key: "w:" + root, row: main, nested: false });

      const sessions = rs.filter((r) => r.path !== root);
      if (!sessions.length) continue;
      out.push({ kind: "sub", key: "c:" + root, label: "claude sessions" });
      for (const [status, word] of GROUPS) {
        const g = sessions.filter((r) => groupOf(r) === status);
        if (!g.length) continue;
        const groupKey = "g:" + root + ":" + status;
        out.push({ kind: "group", key: groupKey, status, word, count: g.length });
        if (collapsed.has(groupKey)) continue;
        const shown = expanded.has(groupKey) ? g : g.slice(0, PER_GROUP);
        for (const r of shown) out.push({ kind: "row", key: "w:" + r.path, row: r, nested: true });
        if (g.length > PER_GROUP) {
          out.push({ kind: "more", key: "m:" + groupKey, listKey: groupKey, hidden: g.length - PER_GROUP });
        }
      }
    }
  }
  return out;
});

// --- views ---------------------------------------------------------------------
function jump(w, a) {
  if (!w) return;
  cmux("workspace.select", { workspace_id: w.id });
  if (a?.surfaceId) cmux("surface.focus", { surface_id: a.surfaceId, workspace_id: w.id });
}

function dotsView(statusesFn) {
  return ForEach(
    { items: () => statusesFn().map((s, i) => ({ id: i + ":" + s, s })), key: (d) => d.id },
    (d) => Circle({ size: 5 }).fill(() => STATUS[d().s]?.color ?? "#7f7f7f66"),
  );
}

function chevron(key) {
  return Image("chevron.right")
    .font(9).weight("semibold").color("tertiary")
    .rotation(() => (tick(), collapsed.has(key()) ? 0 : 90))
    .frame({ width: 12, height: 14 });
}

function sectionHeader(e) {
  return HStack({ spacing: 4 }, [
    Text(() => e().label).font(10).weight("bold").color("tertiary"),
    Spacer(),
    // Collapsed: keep the alert shape visible (needs-input/working only).
    dotsView(() => (collapsed.has(e().key) ? e().dots.filter((s) => s !== "idle") : [])),
  ])
    .paddingHorizontal(8)
    .paddingTop(10)
    .paddingBottom(2)
    .frame({ maxWidth: "infinity" })
    .cursor("pointer")
    .onTap(() => flip(collapsed, e().key));
}

function repoHeader(e) {
  return HStack({ spacing: 6 }, [
    chevron(() => e().key),
    Text(() => base(e().root)).font(12).weight("semibold").lineLimit(1).truncation("tail"),
    Spacer(),
    dotsView(() => e().dots),
  ])
    .paddingLeading(6)
    .paddingTrailing(10)
    .paddingVertical(4)
    .cornerRadius(7)
    .hoverBackground("#7f7f7f1c")
    .frame({ maxWidth: "infinity" })
    .onTap(() => flip(collapsed, e().key));
}

function subHeader(e) {
  return Text(() => e().label)
    .font(10).weight("semibold").color("tertiary")
    .paddingLeading(22)
    .paddingTop(4)
    .frame({ maxWidth: "infinity", alignment: "leading" });
}

function groupHeader(e) {
  return HStack({ spacing: 5 }, [
    chevron(() => e().key),
    Circle({ size: 5 }).fill(() => STATUS[e().status]?.color ?? "#7f7f7f66"),
    Text(() => e().word).font(11).color(() => (e().status === "needs_input" ? "#E8912D" : "secondary")),
    Text(() => String(e().count)).font(10).monospaced().color("tertiary"),
    Spacer(),
  ])
    .paddingLeading(20)
    .paddingTrailing(10)
    .paddingVertical(2)
    .cornerRadius(7)
    .hoverBackground("#7f7f7f1c")
    .frame({ maxWidth: "infinity" })
    .onTap(() => flip(collapsed, e().key));
}

function pinnedRow(e) {
  const w = () => e().w;
  return HStack({ spacing: 6 }, [
    Image("pin.fill").font(8).color("tertiary"),
    Text(() => w().title).font(12).lineLimit(1).truncation("tail")
      .color(() => (w().selected ? "primary" : "secondary")),
    Spacer(),
    Text(() => (w().unread > 0 ? String(w().unread) : "")).font(10).bold().color("#E4573D"),
  ])
    .paddingHorizontal(8)
    .paddingVertical(4)
    .cornerRadius(7)
    .background(() => (w().selected ? "#7f7f7f3d" : null))
    .hoverBackground("#7f7f7f24")
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w(), null));
}

function worktreeRow(e) {
  const r = () => e().row;
  const a = () => r().agent;
  const isMain = () => r().path === r().root;
  const name = () => {
    const branch = r().tab?.branch ?? (isMain() ? r().w?.branch : null);
    const dirty = r().tab?.dirty ?? (isMain() && r().w?.dirty);
    const label = isMain() ? (branch ? branch + " (main checkout)" : "main checkout") : base(r().path);
    return label + (dirty ? "*" : "") + (r().others ? "  +" + r().others : "");
  };
  const time = () => {
    const s = a()?.status;
    if ((s === "working" || s === "needs_input") && a().sinceEpoch) return fmtAge(nowSecs() - secs(a().sinceEpoch));
    return r().at ? fmtAge(nowSecs() - r().at) + " ago" : "";
  };
  // Line 2 is the identity: what this session was asked to do. Nested rows
  // drop the status word, their group header already says it.
  const detail = () => {
    if (!r().w) return "no workspace open";
    const word = e().nested ? "" : STATUS[a()?.status]?.word ?? "";
    const prompt = promptOf(r().w, a());
    return [word, prompt ? "“" + prompt + "”" : ""].filter(Boolean).join(" · ");
  };
  const selected = () => !!r().w?.selected;

  return VStack({ spacing: 1, alignment: "leading" }, [
    HStack({ spacing: 6 }, [
      Circle({ size: 7 }).fill(() => STATUS[a()?.status]?.color ?? "clear"),
      Text(name).font(13).lineLimit(1).truncation("middle")
        .color(() => (selected() ? "primary" : r().w ? "secondary" : "tertiary")),
      Spacer({ minLength: 4 }),
      Text(() => (r().w?.pr ? "#" + r().w.pr.number : "")).font(11).color("secondary")
        .onTap(() => r().w?.pr && openURL(r().w.pr.url)),
      Text(time).font(10).monospaced().color("tertiary"),
    ]),
    Text(detail)
      .font(11).lineLimit(1).truncation("tail")
      .color(() => (a()?.status === "needs_input" ? "#E8912D" : "tertiary"))
      .paddingLeading(13)
      .frame(() => ({ maxWidth: "infinity", height: detail() ? 15 : 0 })),
  ])
    .paddingHorizontal(8)
    .paddingVertical(4)
    .marginLeading(e().nested ? 26 : 12) // stable per key, like kind
    .cornerRadius(7)
    .background(() => (selected() ? "#7f7f7f3d" : null))
    .hoverBackground(() => (selected() ? "#7f7f7f3d" : "#7f7f7f24"))
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(r().w, a()))
    .contextMenu([
      Button("Copy Path", () => clipboard.write(r().path)),
      Button("Mark as Read", () => r().w && cmux("workspace.action", { action: "mark_read", workspace_id: r().w.id })),
    ]);
}

function moreRow(e) {
  return Text(() => (tick(), expanded.has(e().listKey) ? "show fewer" : "+" + e().hidden + " older"))
    .font(11).color("tertiary")
    .paddingLeading(47)
    .paddingVertical(2)
    .frame({ maxWidth: "infinity", alignment: "leading" })
    .cursor("pointer")
    .onTap(() => flip(expanded, e().listKey));
}

sidebar(() =>
  VStack({ spacing: 1 }, [
    ForEach({ items: entries, key: (e) => e.key }, (e) => {
      const kind = e().kind; // stable per key
      if (kind === "section") return sectionHeader(e);
      if (kind === "repo") return repoHeader(e);
      if (kind === "sub") return subHeader(e);
      if (kind === "group") return groupHeader(e);
      if (kind === "pinned") return pinnedRow(e);
      if (kind === "more") return moreRow(e);
      return worktreeRow(e);
    }),
    Text(() => (entries().length ? "" : "No git workspaces. `cw new <name>` starts a worktree session."))
      .font(11).color("tertiary").paddingHorizontal(10),
  ]),
);
