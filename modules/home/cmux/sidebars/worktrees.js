// worktrees: WORK (~/Developer/frontrow, same rule the claude wrapper uses to
// pick the work account) and PRIVATE, each collapsible:
//
//   WORK
//     <repo>
//       >_ main checkout         the repo's own shell workspace (stamped cw:<root>)
//       sessions
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
// Atelier Cave, the terminal palette (modules/home/_palette.nix; text_dim is
// starship's extension). Copied, not generated: this file is symlinked
// out-of-store so edits hot-reload. Contrast on bg1 #19171c: aqua/green 4.8,
// purple 4.2, yellow 4.1, blue 3.9, red 3.7, orange 3.5, text_dim 5.1 — all
// clear the 3:1 icon bar; bg3 (2.9) is only used for hairlines.
const PAL = {
  fg0: "#efecf4",
  text_dim: "#8b8792",
  bg3: "#655f6d",
  blue: "#576ddb",
  aqua: "#398bc6",
  green: "#2a9292",
  orange: "#aa573c",
  purple: "#955ae7",
  red: "#be4678",
  yellow: "#a06e3b",
};
// Nerd Font Material Design glyphs (codepoints read from JetBrainsMono Nerd
// Font's cmap). The sidebar can't pick a font family — .font() takes sizes and
// text styles only — so these draw via CoreText fallback to the installed Nerd
// Fonts. That works for the md range (U+F0001+) and FontAwesome, but Octicons
// and Devicons (U+F4xx, U+E7xx) render as tofu: stay in md.
const NF = {
  briefcase: "\u{F00D6}",
  home: "\u{F02DC}",
  folder: "\u{F024B}",
  folderOpen: "\u{F0770}",
  // starship's git_branch symbol is Powerline U+E0A0, which draws as tofu here
  // (verified live); md source-branch is the closest glyph that renders.
  branch: "\u{F062C}",
  forum: "\u{F028C}",
  alert: "\u{F0362}",
  bolt: "\u{F140B}",
  sleep: "\u{F04B2}",
  pull: "\u{F04C2}",
  chevron: "\u{F0142}",
  dots: "\u{F01D8}",
  pin: "\u{F0403}",
  console: "\u{F018D}",
};
// The fallback font's advance is narrower than md glyph ink and Text clips at
// its advance (right edge cut; padding/frame don't help, verified live). A
// trailing space widens the text itself so the whole glyph draws.
const icon = (glyph, size) => Text(glyph + " ").font(size).lineLimit(1).fixedSize();

const STATUS = {
  needs_input: { color: PAL.orange, rank: 0, word: "needs input", icon: NF.alert },
  working: { color: PAL.blue, rank: 1, word: "working", icon: NF.bolt },
  idle: { color: PAL.text_dim, rank: 2, word: "", icon: NF.sleep },
};
// Section identity, repeated on its repos' folder icons so a repo row says
// which account it belongs to even when the section header is scrolled away.
const SECTION = {
  WORK: { color: PAL.aqua, icon: NF.briefcase },
  PRIVATE: { color: PAL.purple, icon: NF.home },
};
const CLAUDE = PAL.red;
// git_branch/git_status segment of the starship prompt: fg0 on aqua.
const GIT = PAL.aqua;
const PR = PAL.green;
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

// Claude Code titles its terminal "<status glyph> <session name>" (✳ idle,
// spinner frames while working), so a glyph-led tab title names the session.
// The workspace title follows the *focused* tab instead: with a shell focused
// it reads "claude attach <id> ~/D/.home" or a bare path. The agent's own tab
// goes first, but panelId can point at the attaching shell, so any tab counts.
const GLYPH = /^[^\p{L}\p{N}~/.\s]+\s+/u;
function sessionName(w, a) {
  const tabs = w.tabs ?? [];
  const named = [tabs.find((t) => t.id === a?.panelId), ...tabs].find((t) => GLYPH.test(t?.title ?? ""));
  return (named?.title ?? w.title ?? "").replace(GLYPH, "");
}

// --- model ---------------------------------------------------------------------
// The main checkout is exactly one workspace per repo: the one stamped
// "cw:<root>" (made by `cw new`/`cw here`, or by tapping its row). Every other
// workspace is a session: one row per worktree path, one per workspace at a
// repo root (they share the root path but are separate sessions). Sources, in
// order: live agents; stamped workspaces; other git workspaces. Several hits on
// one key: the most urgent (then most recent) one represents it, `others`
// counts the extra agents.
function collectRows(ws) {
  const byKey = new Map();
  const hosted = new Set(); // workspaces already represented by a live agent's row
  const put = (key, path, w, agent, at, session) => {
    const prev = byKey.get(key);
    const better = !prev || rankOf(agent) < rankOf(prev.agent) || (rankOf(agent) === rankOf(prev.agent) && at > prev.at);
    const tab = (w.tabs ?? []).find((t) => t.directory === path && t.branch);
    const row = better ? { path, root: rootOf(path), w, agent, at, tab, session, others: 0 } : prev;
    row.at = Math.max(at, prev?.at ?? 0);
    row.others = (prev?.others ?? 0) + (prev?.agent && agent ? 1 : 0);
    byKey.set(key, row);
  };
  for (const w of ws) {
    if (w.pinned) continue; // triage views render separately
    for (const a of w.agents ?? []) {
      if (a.status === "ended") continue;
      const path = a.directory ?? stampOf(w) ?? w.directory ?? "";
      if (!path) continue;
      const atRoot = rootOf(path) === path;
      put(atRoot ? "s:" + w.id : path, path, w, a, secs(a.lastActivityAt ?? a.sinceEpoch ?? 0), atRoot);
      hosted.add(w.id);
    }
  }
  for (const w of ws) {
    if (w.pinned) continue;
    const stamp = stampOf(w);
    if (stamp) {
      if (!byKey.has(stamp)) put(stamp, stamp, w, null, secs(w.latestAt ?? 0), false);
      continue;
    }
    // A `claude -w` workspace sits at the root while its agent works in the
    // worktree: that agent's row already is this workspace.
    if (hosted.has(w.id)) continue;
    const dir = (isGit(w) || (w.agents ?? []).length) && w.directory;
    if (!dir) continue;
    // Unstamped at a repo root: a session of its own, never the main checkout.
    const atRoot = rootOf(dir) === dir;
    const key = atRoot ? "s:" + w.id : dir;
    if (!byKey.has(key)) put(key, dir, w, null, secs(w.latestAt ?? 0), atRoot);
  }
  return [...byKey.values()];
}

// Collapsed sections/repos/groups and expanded "+N older" lists, local to this view.
const collapsed = new Set();
// Roots whose main workspace was requested but hasn't shown up in the data yet
// (refresh is ~1s): a second tap in that window must not create a twin.
const creating = new Set();
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
    out.push({ kind: "section", key: secKey, label, first: !out.length, dots: dots([...repos.values()].flat()) });
    if (collapsed.has(secKey)) continue;

    for (const w of pinned) out.push({ kind: "pinned", key: "p:" + w.id, w });

    const ordered = [...repos.entries()]
      .map(([root, rs]) => [root, rs.sort((x, y) => y.at - x.at)])
      .sort((x, y) => y[1][0].at - x[1][0].at);
    for (const [i, [root, rs]] of ordered.entries()) {
      const repoKey = "r:" + root;
      // `first` and `section` are part of the key's identity: a repo never
      // changes section, and the first-repo spacing only shifts on reorder.
      out.push({ kind: "repo", key: repoKey + (i ? "" : ":first"), ck: repoKey, root, section: label, first: !i, dots: dots(rs) });
      if (collapsed.has(repoKey)) continue;

      // No workspace at the root: still listed, dimmed, so the repo has an anchor.
      const main = rs.find((r) => r.path === root && !r.session) ?? { path: root, root, w: null, agent: null, at: 0, others: 0 };
      if (main.w) creating.delete(root);
      out.push({ kind: "row", key: "w:" + root, row: main, nested: false });

      const sessions = rs.filter((r) => r.path !== root || r.session);
      if (!sessions.length) continue;
      out.push({ kind: "sub", key: "c:" + root, label: "sessions", count: sessions.length });
      for (const [status, word] of GROUPS) {
        const g = sessions.filter((r) => groupOf(r) === status);
        if (!g.length) continue;
        const groupKey = "g:" + root + ":" + status;
        out.push({ kind: "group", key: groupKey, status, word, count: g.length });
        if (collapsed.has(groupKey)) continue;
        const shown = expanded.has(groupKey) ? g : g.slice(0, PER_GROUP);
        for (const r of shown) out.push({ kind: "row", key: r.session ? "s:" + r.w.id : "w:" + r.path, row: r, nested: true });
        if (g.length > PER_GROUP) {
          out.push({ kind: "more", key: "m:" + groupKey, listKey: groupKey, hidden: g.length - PER_GROUP });
        }
      }
    }
  }
  return out;
});

// --- views ---------------------------------------------------------------------
// Same stamp `cw` uses, so cw and the sidebar agree on which workspace it is.
// (No cmux group from here: the socket call's group params are undocumented.)
function openMain(root) {
  if (creating.has(root)) return;
  creating.add(root);
  cmux("workspace.create", { cwd: root, title: base(root), description: "cw:" + root, focus: true });
}

function jump(w, a) {
  if (!w) return;
  cmux("workspace.select", { workspace_id: w.id });
  if (a?.surfaceId) cmux("surface.focus", { surface_id: a.surfaceId, workspace_id: w.id });
}

function dotsView(statusesFn) {
  return ForEach(
    { items: () => statusesFn().map((s, i) => ({ id: i + ":" + s, s })), key: (d) => d.id },
    (d) => Circle({ size: 5 }).fill(() => STATUS[d().s]?.color ?? PAL.text_dim + "66"),
  );
}

function chevron(key) {
  return icon(NF.chevron, 11).color("tertiary")
    .rotation(() => (tick(), collapsed.has(key()) ? 0 : 90))
    .frame({ width: 12, height: 14 });
}

// Small rounded count pill, tinted like its context.
function pill(textFn, color) {
  return Text(textFn).font(9).weight("semibold").monospaced().color(color)
    .paddingHorizontal(5).paddingVertical(1)
    .background(color + "26").cornerRadius(6)
    .lineLimit(1).fixedSize("horizontal").layoutPriority(2);
}

function sectionHeader(e) {
  const s = SECTION[e().label];
  return HStack({ spacing: 5 }, [
    icon(s.icon, 11).color(s.color),
    Text(() => e().label).font(10).weight("bold").color(s.color),
    Spacer(),
    // Collapsed: keep the alert shape visible (needs-input/working only).
    dotsView(() => (collapsed.has(e().key) ? e().dots.filter((s) => s !== "idle") : [])),
    chevron(() => e().key),
  ])
    .paddingHorizontal(8)
    .paddingTop(e().first ? 8 : 18)
    .paddingBottom(4)
    .frame({ maxWidth: "infinity" })
    .cursor("pointer")
    .onTap(() => flip(collapsed, e().key));
}

function repoHeader(e) {
  const accent = SECTION[e().section].color;
  const header = HStack({ spacing: 6 }, [
    chevron(() => e().ck),
    Text(() => (tick(), collapsed.has(e().ck) ? NF.folder : NF.folderOpen) + " ").font(13).lineLimit(1).fixedSize().color(accent),
    Text(() => base(e().root)).font(12).weight("semibold").lineLimit(1).truncation("tail"),
    Spacer(),
    dotsView(() => e().dots),
  ])
    .paddingLeading(6)
    .paddingTrailing(10)
    .paddingVertical(5)
    .cornerRadius(7)
    .hoverBackground(PAL.text_dim + "1c")
    .frame({ maxWidth: "infinity" })
    .onTap(() => flip(collapsed, e().ck));
  // Breathing room + hairline between repos; the first one hugs its section.
  if (e().first) return header.paddingTop(2);
  return VStack({ spacing: 8, alignment: "leading" }, [Rectangle().fill(PAL.bg3 + "66").frame({ maxWidth: "infinity", height: 1 }).paddingHorizontal(8), header]).paddingTop(10);
}

function subHeader(e) {
  return HStack({ spacing: 5 }, [
    icon(NF.forum, 11).color(CLAUDE),
    Text(() => e().label).font(10).weight("semibold").color("tertiary"),
    pill(() => String(e().count), CLAUDE),
    Spacer(),
  ])
    .paddingLeading(24)
    .paddingTop(6)
    .paddingBottom(1)
    .frame({ maxWidth: "infinity" });
}

function groupHeader(e) {
  const st = STATUS[e().status];
  return HStack({ spacing: 5 }, [
    chevron(() => e().key),
    icon(st.icon, 11).color(st.color).frame({ width: 14 }),
    Text(() => e().word).font(11).weight("medium").color(e().status === "idle" ? "secondary" : st.color),
    pill(() => String(e().count), st.color),
    Spacer(),
  ])
    .paddingLeading(20)
    .paddingTrailing(10)
    .paddingVertical(2)
    .cornerRadius(7)
    .hoverBackground(PAL.text_dim + "1c")
    .frame({ maxWidth: "infinity" })
    .onTap(() => flip(collapsed, e().key));
}

function pinnedRow(e) {
  const w = () => e().w;
  return HStack({ spacing: 6 }, [
    icon(NF.pin, 11).color("tertiary"),
    Text(() => w().title).font(12).lineLimit(1).truncation("tail")
      .color(() => (w().selected ? "primary" : "secondary")),
    Spacer(),
    Text(() => (w().unread > 0 ? String(w().unread) : "")).font(10).bold().color(PAL.red),
  ])
    .paddingHorizontal(8)
    .paddingVertical(4)
    .cornerRadius(7)
    .background(() => (w().selected ? PAL.text_dim + "3d" : null))
    .hoverBackground(PAL.text_dim + "24")
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w(), null));
}

function worktreeRow(e) {
  const r = () => e().row;
  const a = () => r().agent;
  const isMain = () => r().path === r().root && !r().session;
  const name = () => {
    const label = isMain() ? "" : r().session ? sessionName(r().w, a()) || base(r().path) : base(r().path);
    return label + (r().others ? "  +" + r().others : "");
  };
  const branch = () => r().tab?.branch ?? (isMain() ? r().w?.branch : null);
  // cmux exposes only a dirty Bool, not starship's !/?/+ split: "!" stands for
  // any change, untracked included.
  const dirty = () => !!(r().tab?.dirty ?? (isMain() && r().w?.dirty));
  const needs = () => a()?.status === "needs_input";
  // Main checkout: a shell glyph, then a starship-style git segment, " main !"
  // in fg0 on aqua (faded without a workspace). Sessions: the status dot, the
  // group header has the icon.
  const lead = isMain()
    ? HStack({ spacing: 6 }, [
        icon(NF.console, 13).color(() => (r().w ? "secondary" : "tertiary")),
        Text(() => NF.branch + (branch() ? " " + branch() : "") + (dirty() ? " !" : ""))
          .font(11).weight("medium").color(PAL.fg0)
          .paddingHorizontal(5).paddingVertical(1).background(GIT).cornerRadius(4)
          .opacity(() => (r().w ? 1 : 0.5))
          .lineLimit(1).fixedSize("horizontal").layoutPriority(2),
      ])
    : Circle({ size: 7 }).fill(() => STATUS[a()?.status]?.color ?? PAL.bg3).frame({ width: 14 });
  const time = () => {
    const s = a()?.status;
    if ((s === "working" || s === "needs_input") && a().sinceEpoch) return fmtAge(nowSecs() - secs(a().sinceEpoch));
    return r().at ? fmtAge(nowSecs() - r().at) : "";
  };
  // Line 2 is the identity: what this session was asked to do. Nested rows
  // drop the status word, their group header already says it.
  const detail = () => {
    if (!r().w) return isMain() ? "open a shell on the main checkout" : "no workspace open";
    const word = e().nested ? "" : STATUS[a()?.status]?.word ?? "";
    const prompt = promptOf(r().w, a());
    return [word, prompt ? "“" + prompt + "”" : ""].filter(Boolean).join(" · ");
  };
  const selected = () => !!r().w?.selected;

  const body = VStack({ spacing: 1, alignment: "leading" }, [
    HStack({ spacing: 6 }, [
      lead,
      Text(name).font(13).lineLimit(1).truncation(e().row.session ? "tail" : "middle") // titles read left to right, paths at both ends
        .weight(() => (selected() ? "semibold" : "regular"))
        .color(() => (selected() ? "primary" : r().w ? "secondary" : "tertiary")),
      // Sessions carry starship's "!" after the name; the main pill has its own.
      Text("!").font(12).weight("bold").color(GIT).opacity(() => (dirty() && !isMain() ? 1 : 0))
        .frame(() => ({ width: dirty() && !isMain() ? 8 : 0 })),
      Spacer({ minLength: 4 }),
      // Badges keep their width; the name truncates instead (docs: priority 2).
      Text(() => (r().w?.pr ? NF.pull + " " + r().w.pr.number : "")).font(10).weight("semibold").color(PR)
        .paddingHorizontal(() => (r().w?.pr ? 5 : 0))
        .background(() => (r().w?.pr ? PR + "26" : null)).cornerRadius(6)
        .lineLimit(1).fixedSize("horizontal").layoutPriority(2)
        .onTap(() => r().w?.pr && openURL(r().w.pr.url)),
      Text(time).font(10).monospaced().color(() => (needs() ? STATUS.needs_input.color : "tertiary"))
        .lineLimit(1).fixedSize("horizontal").layoutPriority(2),
    ]),
    Text(detail)
      .font(11).lineLimit(1).truncation("tail")
      .color(() => (needs() ? STATUS.needs_input.color : "tertiary"))
      .paddingLeading(18)
      .frame(() => ({ maxWidth: "infinity", height: detail() ? 15 : 0 })),
  ])
    .paddingHorizontal(8)
    .paddingVertical(4)
    .frame({ maxWidth: "infinity" });

  // Leading accent bar: orange while the session waits on you, accent when selected.
  return HStack({ spacing: 0 }, [
    Capsule().fill(() => (needs() ? STATUS.needs_input.color : selected() ? PAL.purple : "clear")).frame({ width: 3, height: 18 }),
    body,
  ])
    .marginLeading(e().nested ? 26 : 12) // stable per key, like kind
    .cornerRadius(7)
    .background(() => (selected() ? PAL.text_dim + "3d" : needs() ? PAL.orange + "1F" : null))
    .hoverBackground(() => (selected() ? PAL.text_dim + "3d" : PAL.text_dim + "24"))
    .frame({ maxWidth: "infinity" })
    .onTap(() => (r().w ? jump(r().w, a()) : isMain() && openMain(r().root)))
    .contextMenu([
      Button("Copy Path", () => clipboard.write(r().path)),
      Button("Mark as Read", () => r().w && cmux("workspace.action", { action: "mark_read", workspace_id: r().w.id })),
    ]);
}

function moreRow(e) {
  return HStack({ spacing: 4 }, [
    icon(NF.dots, 11).color("tertiary"),
    Text(() => (tick(), expanded.has(e().listKey) ? "show fewer" : "+" + e().hidden + " older")).font(11).color("tertiary"),
  ])
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
