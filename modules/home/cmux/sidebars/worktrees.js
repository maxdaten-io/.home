// worktrees: one cmux workspace per git worktree, grouped by project, split
// into WORK (~/Developer/frontrow — same rule the claude wrapper uses to pick
// the work account) and PRIVATE. Pairs with `cw` (../cw.sh), which stamps each
// workspace's description with `cw:<worktree path>`.
//
// Why not w.branch / w.directory: they follow the *focused* pane, and the
// claude pane's shell sits in the repo root while claude runs in the worktree,
// so a focused claude pane reports `main`. Path comes from the stamp, else the
// live agent's directory; branch/dirty from the tab sitting in that path.
//
// Edits hot-reload: this file is symlinked out of the Nix store on purpose.

const WORK = "/Developer/frontrow/";
const COLOR = { needs_input: "#E8912D", working: "#4C9EEB", idle: "#8E8E93" };
const PR_COLOR = { open: "#3FB950", merged: "#A371F7", closed: "#8E8E93" };

// --- derived data --------------------------------------------------------------
// Ended sessions linger in w.agents (newest first) with stale directories.
const live = (w) => (w.agents ?? []).find((a) => a.status !== "ended");

function worktreePath(w) {
  if (w.description && w.description.startsWith("cw:")) return w.description.slice(3);
  return live(w)?.directory ?? w.directory ?? "";
}

// <repo>/.claude/worktrees/<name> (claude default) or <repo>.worktrees/<name>
// (front-row-ai's WorktreeCreate hook) -> <repo>.
function projectOf(path) {
  const m = path.match(/^(.*)\/\.claude\/worktrees\/[^/]+/) ?? path.match(/^(.*)\.worktrees\/[^/]+/);
  return (m ? m[1] : path).split("/").filter(Boolean).pop() ?? "?";
}

function gitOf(w) {
  const p = worktreePath(w);
  const t = (w.tabs ?? []).find((t) => t.directory === p && t.branch);
  return t ? { branch: t.branch, dirty: !!t.dirty } : { branch: w.branch, dirty: !!w.dirty };
}

// "2● 1⏵": needs-input / working counts, so a collapsed header still alerts.
function counts(members) {
  let ask = 0, run = 0;
  for (const w of members) {
    const s = live(w)?.status;
    if (s === "needs_input") ask++;
    else if (s === "working") run++;
  }
  return [ask ? ask + "●" : "", run ? run + "⏵" : ""].filter(Boolean).join(" ");
}

// --- collapse state ------------------------------------------------------------
// Native groups persist collapse in cmux (optimistic local override until the
// data catches up). Sections and derived buckets are local to this sidebar.
const groupOverride = new Map();
const localCollapsed = new Set();
const [tick, setTick] = signal(0);
const bump = () => setTick(tick() + 1);

function isCollapsed(g) {
  tick();
  if (groupOverride.has(g.id)) {
    if (groupOverride.get(g.id) === g.collapsed) groupOverride.delete(g.id);
    else return groupOverride.get(g.id);
  }
  return g.collapsed;
}

function toggleGroup(g) {
  const next = !isCollapsed(g);
  groupOverride.set(g.id, next);
  bump();
  cmux(next ? "workspace.group.collapse" : "workspace.group.expand", { group_id: g.id });
}

function toggleLocal(key) {
  if (localCollapsed.has(key)) localCollapsed.delete(key);
  else localCollapsed.add(key);
  bump();
}

const isLocalCollapsed = (key) => (tick(), localCollapsed.has(key));

// --- layout --------------------------------------------------------------------
// One flat list: section header, pinned rows (the `claude agents` triage view),
// native groups (cw-created: one per repo), then ungrouped strays bucketed by
// derived project name.
const entries = computed(() => {
  const ws = data.workspaces() ?? [];
  const groups = data.groups() ?? [];
  const byId = new Map(ws.map((w) => [w.id, w]));
  const out = [];
  for (const [label, work] of [["WORK", true], ["PRIVATE", false]]) {
    const inSection = (w) => worktreePath(w).includes(WORK) === work;
    const secGroups = groups.filter((g) => byId.has(g.anchorId) && inSection(byId.get(g.anchorId)));
    const strays = ws.filter((w) => !w.group && inSection(w));
    if (!secGroups.length && !strays.length) continue;

    const secKey = "s:" + label;
    out.push({ kind: "section", id: secKey, label });
    if (isLocalCollapsed(secKey)) continue;

    for (const w of strays.filter((w) => w.pinned)) out.push({ kind: "ws", id: w.id, depth: 0 });

    for (const g of secGroups) {
      out.push({ kind: "group", id: "g:" + g.id, groupId: g.id });
      if (isCollapsed(g)) continue;
      for (const w of ws) if (w.group === g.id && w.id !== g.anchorId) out.push({ kind: "ws", id: w.id, depth: 1 });
    }

    const buckets = new Map();
    for (const w of strays.filter((w) => !w.pinned)) {
      const p = projectOf(worktreePath(w));
      if (!buckets.has(p)) buckets.set(p, []);
      buckets.get(p).push(w);
    }
    for (const [p, members] of buckets) {
      const key = "d:" + label + ":" + p;
      out.push({ kind: "bucket", id: key, label: p, work });
      if (isLocalCollapsed(key)) continue;
      for (const w of members) out.push({ kind: "ws", id: w.id, depth: 1 });
    }
  }
  return out;
});

// --- views ---------------------------------------------------------------------
const wsById = (id) => (data.workspaces() ?? []).find((w) => w.id === id);
const select = (id) => id && cmux("workspace.select", { workspace_id: id });

function sectionHeader(entry) {
  const members = () =>
    (data.workspaces() ?? []).filter((w) => worktreePath(w).includes(WORK) === (entry.label === "WORK"));
  return HStack({ spacing: 6 }, [
    Text(entry.label).font(10).weight("bold").color("tertiary"),
    Text(() => (isLocalCollapsed(entry.id) ? counts(members()) : "")).font(10).color("#E8912D"),
    Spacer(),
  ])
    .paddingHorizontal(8)
    .paddingTop(10)
    .paddingBottom(2)
    .frame({ maxWidth: "infinity" })
    .cursor("pointer")
    .onTap(() => toggleLocal(entry.id));
}

function chevron(collapsed) {
  return Image("chevron.right")
    .font(9).weight("semibold").color("tertiary")
    .rotation(() => (collapsed() ? 0 : 90))
    .frame({ width: 12, height: 14 });
}

function headerRow(collapsed, onToggle, label, members, onTap, menu) {
  const row = HStack({ spacing: 6 }, [
    chevron(collapsed).onTap(onToggle),
    Text(label).font(12).weight("semibold").lineLimit(1).truncation("tail"),
    Spacer(),
    Text(() => counts(members())).font(11).color("#E8912D"),
  ])
    .paddingLeading(6)
    .paddingTrailing(10)
    .paddingVertical(4)
    .cornerRadius(7)
    .hoverBackground("#7f7f7f1c")
    .frame({ maxWidth: "infinity" })
    .onTap(onTap);
  return menu ? row.contextMenu(menu) : row;
}

function groupHeader(entry) {
  const g = () => (data.groups() ?? []).find((x) => x.id === entry.groupId) ?? { id: entry.groupId, name: "" };
  const members = () => (data.workspaces() ?? []).filter((w) => w.group === entry.groupId);
  return headerRow(
    () => isCollapsed(g()),
    () => toggleGroup(g()),
    () => g().name,
    members,
    () => select(g().anchorId), // anchor = the repo-root workspace cw created
    [
      Button(() => (isCollapsed(g()) ? "Expand" : "Collapse"), () => toggleGroup(g())),
      Button(() => (g().pinned ? "Unpin Group" : "Pin Group"), () =>
        cmux("workspace.group.action", { group_id: entry.groupId, action: g().pinned ? "unpin" : "pin" })),
      Divider(),
      Button("Ungroup", () => cmux("workspace.group.action", { group_id: entry.groupId, action: "ungroup" })),
    ],
  );
}

function bucketHeader(entry) {
  // Recomputed, not captured: the template runs once per key, membership changes.
  const members = () =>
    (data.workspaces() ?? []).filter((w) =>
      !w.group && !w.pinned && worktreePath(w).includes(WORK) === entry.work && projectOf(worktreePath(w)) === entry.label);
  return headerRow(
    () => isLocalCollapsed(entry.id),
    () => toggleLocal(entry.id),
    entry.label,
    members,
    () => toggleLocal(entry.id),
    null,
  ).opacity(0.85);
}

function wsRow(entry) {
  const w = () => wsById(entry.id);
  const agent = () => (w() ? live(w()) : undefined);
  const status = () => agent()?.status;
  const git = () => (w() ? gitOf(w()) : {});
  const pr = () => w()?.pr;
  const age = () => {
    let since = agent()?.sinceEpoch ?? w()?.latestAt;
    if (!since || !status() || status() === "idle") return "";
    if (since > 1e12) since /= 1000; // ms vs s isn't documented; accept both
    // data.clock() is documented but undefined in the JS runtime (TypeError
    // seen live), so fall back to Date; rows re-render on the ~1s data tick.
    const now = data.clock?.()?.epoch ?? Date.now() / 1000;
    const min = Math.max(0, Math.floor((now - since) / 60));
    return min < 60 ? min + "m" : Math.floor(min / 60) + "h";
  };
  // Line 2 only while it matters: the first prompt is what identifies a session.
  const detail = () => {
    if (status() !== "needs_input" && status() !== "working") return "";
    const what = status() === "needs_input" ? "needs input" : "working";
    // agents[].title is absent in practice; latestPrompt can be a harness
    // injection like `<task-notification>…`, which identifies nothing.
    const prompt = [agent()?.title, w()?.latestPrompt].find((p) => p && !p.trimStart().startsWith("<"));
    return prompt ? what + " · “" + prompt + "”" : what;
  };
  const selected = () => !!w()?.selected;

  return VStack({ spacing: 1, alignment: "leading" }, [
    HStack({ spacing: 6 }, [
      Circle({ size: 7 }).fill(() => COLOR[status()] ?? "clear"),
      Text(() => (w()?.title ?? "") + (git().dirty ? "*" : ""))
        .font(13).lineLimit(1).truncation("tail").marquee()
        .color(() => (selected() ? "primary" : "secondary")),
      Spacer({ minLength: 4 }),
      Text(() => (w()?.unread > 0 ? String(w().unread) : "")).font(10).bold().color("#E4573D"),
      Text(() => (pr() ? "#" + pr().number : ""))
        .font(11).color(() => PR_COLOR[pr()?.status] ?? "secondary")
        .onTap(() => pr() && openURL(pr().url)),
      Text(age).font(11).monospaced().color("tertiary"),
    ]),
    Text(detail)
      .font(11).lineLimit(1).truncation("tail")
      .color(() => (status() === "needs_input" ? "#E8912D" : "tertiary"))
      .paddingLeading(13)
      .frame(() => ({ maxWidth: "infinity", height: detail() ? 15 : 0 })),
  ])
    .paddingHorizontal(8)
    .paddingVertical(4)
    .marginLeading(entry.depth ? 12 : 0)
    .cornerRadius(7)
    .background(() => (selected() ? "#7f7f7f3d" : null))
    .hoverBackground(() => (selected() ? "#7f7f7f3d" : "#7f7f7f24"))
    .frame({ maxWidth: "infinity" })
    .onTap(() => select(entry.id))
    .contextMenu([
      Button(() => (w()?.pinned ? "Unpin" : "Pin"), () =>
        cmux("workspace.action", { action: w()?.pinned ? "unpin" : "pin", workspace_id: entry.id })),
      Button("Mark as Read", () => cmux("workspace.action", { action: "mark_read", workspace_id: entry.id })),
      Divider(),
      Button("Close", () => cmux("workspace.close", { workspace_id: entry.id })).destructive(),
    ]);
}

sidebar(() =>
  VStack({ spacing: 1 }, [
    ForEach({ items: entries, key: (e) => e.id }, (e) => {
      const entry = e(); // kind and ids are stable per key
      if (entry.kind === "section") return sectionHeader(entry);
      if (entry.kind === "group") return groupHeader(entry);
      if (entry.kind === "bucket") return bucketHeader(entry);
      return wsRow(entry);
    }),
  ]),
);
