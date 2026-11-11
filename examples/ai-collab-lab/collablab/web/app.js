"use strict";

/* AI Collab Lab front end. Plain JavaScript, no external dependencies. */

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
const USER = "user";
const STATUS_LABELS = { todo: "To do", in_progress: "In progress", review: "Review", blocked: "Blocked", done: "Done" };
const SUGGESTIONS = [
  "Build a temperature converter for Celsius, Fahrenheit and Kelvin",
  "Create a VAT calculator with a 7% rate",
  "Make a BMI calculator with WHO categories",
  "Write a palindrome checker",
  "status",
];
const TEXTAREA_FIELDS = new Set(["content", "text", "body", "description", "note", "result", "value"]);

const ui = {
  meta: null,
  snap: null,
  seq: 0,
  messages: [],
  events: [],
  tab: "chat",
  conv: "#general",
  viewed: {},
  file: null,
  editing: false,
  preview: true,
  tool: null,
  doc: null,
  sig: {},
  renderedEvents: 0,
  online: false,
};

// ------------------------------------------------------------------ helpers
function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}

function rich(text) {
  let html = esc(text);
  html = html.replace(/\b((?:src|tests|docs|notes|reports)\/[A-Za-z0-9_.\/-]+\.[a-z]+)/g, '<a data-file="$1">$1</a>');
  html = html.replace(/(^|[\s(])@([a-z][a-z0-9_-]{0,31})/g, '$1<span class="mention">@$2</span>');
  html = html.replace(/\b(T-\d+)\b/g, '<a data-task="$1">$1</a>');
  return html;
}

function inline(text) {
  return esc(text).replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
}

function markdown(source) {
  const out = [];
  let code = null;
  let list = false;
  const closeList = () => { if (list) { out.push("</ul>"); list = false; } };
  for (const line of source.split("\n")) {
    if (/^```/.test(line)) {
      if (code === null) { closeList(); code = []; } else { out.push(`<pre><code>${esc(code.join("\n"))}</code></pre>`); code = null; }
      continue;
    }
    if (code !== null) { code.push(line); continue; }
    const heading = line.match(/^(#{1,3})\s+(.*)$/);
    if (heading) { closeList(); out.push(`<h${heading[1].length}>${inline(heading[2])}</h${heading[1].length}>`); continue; }
    const item = line.match(/^\s*[-*]\s+(.*)$/) || line.match(/^\s*\d+\.\s+(.*)$/);
    if (item) { if (!list) { out.push("<ul>"); list = true; } out.push(`<li>${inline(item[1])}</li>`); continue; }
    closeList();
    if (/^>\s?/.test(line)) { out.push(`<blockquote>${inline(line.replace(/^>\s?/, ""))}</blockquote>`); continue; }
    if (line.trim()) out.push(`<p>${inline(line)}</p>`);
  }
  if (code !== null) out.push(`<pre><code>${esc(code.join("\n"))}</code></pre>`);
  closeList();
  return out.join("");
}

function agent(id) { return ui.snap?.agents.find((a) => a.id === id); }
function nameOf(id) { if (id === USER) return "You"; if (id === "system") return "System"; return agent(id)?.name || id; }
function colorOf(id) { if (id === USER) return "#5b6178"; if (id === "system") return "#8a8fa3"; return agent(id)?.color || "#8a8fa3"; }
function initials(id) { return nameOf(id).slice(0, 1).toUpperCase(); }
function avatar(id, small = true) {
  return `<span class="avatar${small ? " sm" : ""}" style="--agent:${esc(colorOf(id))}">${esc(initials(id))}</span>`;
}
function changed(key, value) {
  const sig = typeof value === "string" ? value : JSON.stringify(value);
  if (ui.sig[key] === sig) return false;
  ui.sig[key] = sig;
  return true;
}

function toast(text, bad = false) {
  const node = document.createElement("div");
  node.className = "toast" + (bad ? " bad" : "");
  node.textContent = text;
  $("#toasts").appendChild(node);
  setTimeout(() => node.remove(), bad ? 6000 : 3000);
}

const api = {
  async get(path) {
    const response = await fetch(path, { headers: { Accept: "application/json" } });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error?.message || response.statusText);
    return data;
  },
  async post(path, body) {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Collab-Lab": "1" },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok || data.ok === false) throw new Error(data.error?.message || response.statusText);
    return data;
  },
};

async function tool(name, args) {
  return api.post("/api/tool", { name, args });
}

async function safely(action, success) {
  try {
    const result = await action();
    if (success) toast(success);
    await refresh();
    return result;
  } catch (error) {
    toast(error.message, true);
    return null;
  }
}

// ------------------------------------------------------------------ polling
let refreshChain = Promise.resolve();

// Refreshes run one at a time so incremental merges never interleave.
function refresh(full = false) {
  const next = refreshChain.then(() => pull(full));
  refreshChain = next.catch(() => {});
  return next;
}

async function pull(full) {
  if (full) { ui.seq = 0; ui.messages = []; ui.events = []; ui.renderedEvents = 0; ui.sig = {}; $("#timeline").innerHTML = ""; }
  const data = await api.get(`/api/state?since=${ui.seq}`);
  if (data.seq < ui.seq) return pull(true);
  ui.messages.push(...data.messages);
  ui.events.push(...data.events);
  if (ui.events.length > 5000) { ui.events.splice(0, ui.events.length - 5000); ui.renderedEvents = 0; $("#timeline").innerHTML = ""; }
  ui.seq = data.seq;
  ui.snap = data;
  ui.online = true;
  render();
}

async function loop() {
  try {
    await refresh();
    setTimeout(loop, ui.snap?.engine.running ? 500 : 1000);
  } catch (error) {
    ui.online = false;
    renderEngine();
    setTimeout(loop, 2000);
  }
}

// ------------------------------------------------------------------- render
function render() {
  renderEngine();
  renderTeam();
  renderConversations();
  renderMessages();
  renderComposerTargets();
  renderKanban();
  renderFiles();
  renderTimeline();
  if (ui.tab === "network") renderNetwork();
  renderSide();
  renderTools();
}

function renderEngine() {
  const box = $("#engine-status");
  if (!ui.online) { box.dataset.status = "offline"; $(".label", box).textContent = "server offline — retrying"; return; }
  const engine = ui.snap.engine;
  box.dataset.status = engine.running ? "running" : engine.status;
  $(".label", box).textContent = engine.running ? "running" : engine.status;
  $("#tick").textContent = `tick ${ui.snap.tick}`;
  $('[data-control="run"]').disabled = engine.running;
  $('[data-control="pause"]').disabled = !engine.running;
  $('[data-control="step"]').disabled = engine.running;
  $("#engine-detail").textContent = engine.detail || "";
}

function renderTeam() {
  const agents = ui.snap.agents;
  if (!changed("team", agents)) return;
  $("#team-list").innerHTML = agents.length ? agents.map((a) => `
    <div class="agent" data-agent="${esc(a.id)}" data-status="${esc(a.status)}" style="--agent:${esc(a.color)}" tabindex="0">
      <span class="avatar">${esc(a.name.slice(0, 1).toUpperCase())}<span class="status-dot"></span></span>
      <div class="name">${esc(a.name)} <i class="badge ${a.brain === "claude" ? "ai" : "sim"}">${a.brain === "claude" ? "CLAUDE" : "SIM"}</i></div>
      <div class="role">${esc(a.role)} · ${esc(a.status)}</div>
      <div class="detail" title="${esc(a.status_detail)}">${esc(a.status_detail || `${a.stats.turns} turns · ${a.stats.tool_calls} tool calls · ${a.stats.messages_sent} msgs`)}</div>
      <div class="actions">
        <button class="btn small" data-nudge="${esc(a.id)}" title="Wake this agent">Nudge</button>
        <button class="btn small" data-dm="${esc(a.id)}" title="Direct message">DM</button>
      </div>
    </div>`).join("") : '<p class="muted small">No agents. Add one or load a scenario.</p>';
  const select = $("#filter-actor");
  const current = select.value;
  select.innerHTML = '<option value="">Everyone</option><option value="user">You</option>' +
    agents.map((a) => `<option value="${esc(a.id)}">${esc(a.name)}</option>`).join("");
  select.value = current;
}

function conversationKeys() {
  const keys = ui.snap.channels.map((c) => c.name);
  return { channels: keys, direct: ui.snap.agents.map((a) => `@${a.id}`) };
}

function inConversation(message, key) {
  if (key === "*") return true;
  if (key.startsWith("#")) return message.to === key;
  const other = key.slice(1);
  return !message.to.startsWith("#") && ((message.sender === USER && message.to === other) || (message.sender === other && message.to === USER));
}

function renderConversations() {
  const { channels, direct } = conversationKeys();
  const unread = (key) => ui.messages.filter((m) => m.sender !== USER && m.seq > (ui.viewed[key] || 0) && inConversation(m, key)).length;
  const item = (key, label, icon) => {
    const count = key === ui.conv ? 0 : unread(key);
    return `<button class="conv${key === ui.conv ? " active" : ""}" data-conv="${esc(key)}">${icon}<span>${esc(label)}</span>${count ? `<span class="unread">${count}</span>` : ""}</button>`;
  };
  const html = '<div class="conv-group">Channels</div>' + channels.map((c) => item(c, c.slice(1), '<span class="hash">#</span>')).join("") +
    '<div class="conv-group">Direct</div>' + direct.map((d) => item(d, nameOf(d.slice(1)), avatar(d.slice(1)))).join("") +
    '<div class="conv-group">Observe</div>' + item("*", "All traffic", '<span class="hash">∗</span>');
  if (changed("conversations", html)) $("#conversations").innerHTML = html;
}

function renderMessages() {
  const list = ui.messages.filter((m) => inConversation(m, ui.conv));
  const key = `${ui.conv}|${list.length}|${ui.snap.agents.map((a) => a.color + a.name).join()}`;
  ui.viewed[ui.conv] = ui.seq;
  const asked = ui.messages.some((m) => m.sender === USER);
  const chips = asked ? "" : SUGGESTIONS.map((s) => `<button class="chip" data-suggest="${esc(s)}">${esc(s)}</button>`).join("");
  if (changed("chips", chips)) $("#suggestions").innerHTML = chips;
  if (!changed("messages", key)) return;
  const head = ui.conv === "*" ? "<strong>All traffic</strong><span class=\"muted small\">every message, including agent-to-agent DMs</span>"
    : ui.conv.startsWith("#") ? `<strong>${esc(ui.conv)}</strong><span class="muted small">${esc(ui.snap.channels.find((c) => c.name === ui.conv)?.topic || "")}</span>`
      : `<strong>${esc(nameOf(ui.conv.slice(1)))}</strong><span class="muted small">direct messages · ${esc(agent(ui.conv.slice(1))?.role || "")}</span>`;
  $("#thread-head").innerHTML = head;
  const box = $("#messages");
  const nearBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
  box.innerHTML = list.length ? list.slice(-400).map((m) => {
    const route = ui.conv === "*" ? `<span class="route">→ ${esc(m.to.startsWith("#") ? m.to : nameOf(m.to))}</span>` : "";
    const cls = m.sender === USER ? " mine" : (m.mentions.includes(USER) ? " mentioned" : "");
    return `<div class="msg${cls}">${avatar(m.sender)}<div><div class="meta"><b>${esc(nameOf(m.sender))}</b>${route}<span>tick ${m.tick}</span><span>${esc(m.id)}</span></div><div class="bubble"><div class="body">${rich(m.text)}</div></div></div></div>`;
  }).join("") : '<div class="empty">No messages here yet.</div>';
  if (nearBottom || list.length < 3) box.scrollTop = box.scrollHeight;
}

function renderComposerTargets() {
  const { channels } = conversationKeys();
  const options = channels.map((c) => [c, c]).concat(ui.snap.agents.map((a) => [a.id, `@${a.name} (${a.role})`]));
  const html = options.map(([value, label]) => `<option value="${esc(value)}">${esc(label)}</option>`).join("");
  const select = $("#composer-to");
  if (changed("targets", html)) { const current = select.value; select.innerHTML = html; select.value = current || "#general"; }
  if (changed("target-conv", ui.conv)) {
    select.value = ui.conv === "*" ? "#general" : ui.conv.startsWith("#") ? ui.conv : ui.conv.slice(1);
  }
}

function renderKanban() {
  const tasks = ui.snap.tasks;
  $("#count-tasks").textContent = tasks.length ? `${tasks.filter((t) => t.status === "done").length}/${tasks.length}` : "";
  if (!changed("kanban", [tasks, ui.snap.agents.map((a) => [a.id, a.name, a.color])])) return;
  const byId = Object.fromEntries(tasks.map((t) => [t.id, t]));
  $("#kanban").innerHTML = Object.entries(STATUS_LABELS).map(([status, label]) => {
    const cards = tasks.filter((t) => t.status === status);
    return `<div class="column" data-status="${status}"><h4>${label}<span>${cards.length}</span></h4>${cards.map((t) => {
      const waiting = t.depends_on.filter((d) => byId[d]?.status !== "done");
      const deps = t.depends_on.length ? `<span class="pill ${waiting.length ? "wait" : "ok"}">${waiting.length ? "waits " + esc(waiting.join(", ")) : "deps done"}</span>` : "";
      const owner = t.assignee ? `${avatar(t.assignee)}<span>${esc(nameOf(t.assignee))}</span>` : '<span class="muted">unassigned</span>';
      return `<div class="task" data-task="${esc(t.id)}" style="--agent:${esc(t.assignee ? colorOf(t.assignee) : "transparent")}"><div class="id">${esc(t.id)}</div><div class="title">${esc(t.title)}</div><div class="foot">${owner}${deps}${t.notes.length ? `<span>${t.notes.length} notes</span>` : ""}</div></div>`;
    }).join("")}</div>`;
  }).join("");
}

function renderFiles() {
  const files = ui.snap.files.slice().sort((a, b) => a.path.localeCompare(b.path));
  $("#count-files").textContent = files.length || "";
  if (changed("files", [files, ui.file])) {
    let folder = null;
    $("#file-tree").innerHTML = files.length ? files.map((f) => {
      const top = f.path.includes("/") ? f.path.split("/")[0] : "(root)";
      const header = top !== folder ? `<div class="tree-folder">${esc(top)}</div>` : "";
      folder = top;
      return `${header}<button class="tree-item${f.path === ui.file ? " active" : ""}" data-file="${esc(f.path)}"><span class="path">${esc(f.path.includes("/") ? f.path.slice(top.length + 1) : f.path)}</span><span class="muted small">v${f.version}</span></button>`;
    }).join("") : '<p class="muted small" style="padding:0 14px">Empty workspace.</p>';
  }
  if (ui.file && !ui.editing) {
    const record = files.find((f) => f.path === ui.file);
    if (!record) { ui.file = null; $("#file-view").innerHTML = '<div class="empty">The file was deleted.</div>'; }
    else if (changed("file-view", [record.path, record.version, ui.preview])) loadFile(record.path);
  }
}

async function loadFile(path) {
  try {
    const record = await api.get(`/api/file?path=${encodeURIComponent(path)}`);
    if (ui.file !== path || ui.editing) return;
    const isMarkdown = path.endsWith(".md");
    const body = isMarkdown && ui.preview ? `<div class="markdown">${markdown(record.content)}</div>`
      : `<pre class="code">${record.content.split("\n").map((line, i) => `<span class="ln">${i + 1}</span>${esc(line)}`).join("\n")}</pre>`;
    $("#file-view").innerHTML = `<div class="file-head"><div><span class="path">${esc(record.path)}</span> <span class="muted small">v${record.version} · ${esc(nameOf(record.author))} · ${record.size} chars</span></div>
      <div>${isMarkdown ? `<button class="btn small" data-file-action="preview">${ui.preview ? "Raw" : "Preview"}</button>` : ""}
      <button class="btn small" data-file-action="edit">Edit</button><button class="btn small danger" data-file-action="delete">Delete</button></div></div>${body}`;
  } catch (error) {
    toast(error.message, true);
  }
}

const EVENT_ICONS = { message: "💬", tool_call: "🛠", task_created: "🗂", task_updated: "🗂", file_written: "📄", file_deleted: "🗑", thought: "💭",
  poll_created: "🗳", vote: "🗳", poll_closed: "🏁", fact_set: "📌", fact_cleared: "📌", error: "⚠️", turn: "✅", agent_added: "👋",
  agent_removed: "👋", knowledge_added: "📚", nudge: "👉", system: "⚙", channel_created: "#", agent_updated: "⚙" };

function eventMatches(event) {
  const type = $("#filter-type").value;
  const actor = $("#filter-actor").value;
  if (actor && event.actor !== actor) return false;
  if (!type) return true;
  if (type === "task") return event.type.startsWith("task_");
  if (type === "file") return event.type.startsWith("file_");
  if (type === "poll") return ["poll_created", "vote", "poll_closed"].includes(event.type);
  return event.type === type;
}

function eventRow(event) {
  const details = event.type === "tool_call"
    ? `<details><summary class="muted small">arguments &amp; result</summary><pre>${esc(JSON.stringify(event.data.args, null, 1))}</pre><pre>${esc(event.data.result || "")}</pre></details>` : "";
  return `<li class="event ${esc(event.type)}"><span class="t">t${event.tick}</span><span>${EVENT_ICONS[event.type] || "•"}</span><div><span class="who" style="color:${esc(colorOf(event.actor))}">${esc(nameOf(event.actor))}</span> <span class="summary">${rich(event.summary)}</span>${details}</div></li>`;
}

function renderTimeline(reset = false) {
  const list = $("#timeline");
  if (reset) { list.innerHTML = ""; ui.renderedEvents = 0; }
  const fresh = ui.events.slice(ui.renderedEvents).filter(eventMatches);
  ui.renderedEvents = ui.events.length;
  if (!fresh.length) { if (!list.children.length) list.innerHTML = '<li class="empty">No events yet.</li>'; return; }
  $(".empty", list)?.remove();
  list.insertAdjacentHTML("beforeend", fresh.slice(-600).map(eventRow).join(""));
  while (list.children.length > 800) list.firstElementChild.remove();
  if ($("#follow-activity").checked && ui.tab === "activity") list.parentElement.scrollTop = list.parentElement.scrollHeight;
}

function renderNetwork() {
  const agents = ui.snap.agents;
  const sig = [agents.map((a) => [a.id, a.status, a.color]), ui.messages.length, ui.snap.tick];
  if (!changed("network", sig)) return;
  const width = 640, height = 460, cx = width / 2, cy = height / 2;
  const nodes = {};
  nodes[USER] = { x: cx, y: cy, label: "You", sub: "operator", color: colorOf(USER), r: 26 };
  agents.forEach((a, i) => {
    const angle = (i / Math.max(agents.length, 1)) * Math.PI * 2 - Math.PI / 2;
    nodes[a.id] = { x: cx + Math.cos(angle) * 180, y: cy + Math.sin(angle) * 170, label: a.name, sub: a.role, color: a.color, r: 22, status: a.status };
  });
  ui.snap.channels.forEach((c, i) => {
    const angle = (i / ui.snap.channels.length) * Math.PI * 2;
    nodes[c.name] = { x: cx + Math.cos(angle) * 105, y: cy + Math.sin(angle) * 70, label: c.name, sub: "channel", color: "#9aa1b8", r: 14, channel: true };
  });
  const edges = {};
  const pulses = [];
  for (const m of ui.messages) {
    if (!nodes[m.sender] || !nodes[m.to]) continue;
    const key = [m.sender, m.to].sort().join("|");
    edges[key] = (edges[key] || 0) + 1;
    if (ui.snap.tick - m.tick <= 1) pulses.push(m);
  }
  const svg = [];
  for (const [key, count] of Object.entries(edges)) {
    const [a, b] = key.split("|");
    svg.push(`<line class="edge" x1="${nodes[a].x}" y1="${nodes[a].y}" x2="${nodes[b].x}" y2="${nodes[b].y}" stroke-width="${Math.min(1 + Math.log2(count + 1) * 1.6, 9).toFixed(1)}"/>`);
  }
  for (const m of pulses.slice(-30)) {
    const a = nodes[m.sender], b = nodes[m.to];
    svg.push(`<circle class="pulse" r="4"><animateMotion dur="1.4s" repeatCount="indefinite" path="M${a.x},${a.y} L${b.x},${b.y}"/></circle>`);
  }
  for (const [id, n] of Object.entries(nodes)) {
    const active = n.status === "working" || n.status === "thinking";
    const ring = n.channel ? "" : `<circle class="ring" cx="${n.x}" cy="${n.y}" r="${n.r + 5}" stroke="${active ? "var(--ok)" : n.status === "error" ? "var(--bad)" : "transparent"}"/>`;
    const shape = n.channel ? `<rect x="${n.x - n.r}" y="${n.y - n.r}" width="${n.r * 2}" height="${n.r * 2}" rx="5" fill="${esc(n.color)}" opacity=".55"/>`
      : `<circle cx="${n.x}" cy="${n.y}" r="${n.r}" fill="${esc(n.color)}"/><text x="${n.x}" y="${n.y + 5}" class="initial">${esc(n.label.slice(0, 1))}</text>`;
    svg.push(`<g data-node="${esc(id)}">${ring}${shape}<text class="label" x="${n.x}" y="${n.y + n.r + 16}">${esc(n.label)}</text><text class="sub" x="${n.x}" y="${n.y + n.r + 28}">${esc(n.sub)}</text></g>`);
  }
  $("#network").innerHTML = svg.join("");
}

function renderSide() {
  const s = ui.snap;
  const totals = s.agents.reduce((acc, a) => { acc.tools += a.stats.tool_calls; acc.tokens += a.stats.input_tokens + a.stats.output_tokens; return acc; }, { tools: 0, tokens: 0 });
  const done = s.tasks.filter((t) => t.status === "done").length;
  const max = s.settings.max_llm_calls || 1;
  const html = `<dt>Agents</dt><dd>${s.agents.length} (${s.engine.awake.length} awake)</dd>
    <dt>Tasks done</dt><dd>${done} / ${s.tasks.length}</dd>
    <dt>Messages</dt><dd>${ui.messages.length}</dd>
    <dt>Tool calls</dt><dd>${totals.tools}</dd>
    <dt>Files</dt><dd>${s.files.length}</dd>
    <dt>Claude calls</dt><dd>${s.engine.llm_calls} / ${s.settings.max_llm_calls}</dd>
    <div class="meter"><span style="width:${Math.min(100, (s.engine.llm_calls / max) * 100).toFixed(0)}%"></span></div>
    <dt>Tokens</dt><dd>${totals.tokens.toLocaleString()}</dd>
    <dt>Code execution</dt><dd>${s.settings.allow_code_execution ? "on" : "off"}</dd>`;
  if (changed("stats", html)) $("#stats").innerHTML = html;
  if (changed("polls", s.polls)) {
    $("#polls").innerHTML = s.polls.length ? s.polls.slice().reverse().map((p) => {
      const tally = {}; p.options.forEach((o) => { tally[o] = 0; }); Object.values(p.votes).forEach((v) => { tally[v.option] += 1; });
      const total = Math.max(1, Object.values(tally).reduce((a, b) => a + b, 0));
      return `<div class="poll"><div class="q">${esc(p.id)} · ${esc(p.question)}</div>${p.options.map((o) => `<div class="bar"><span>${esc(o)}</span><span class="track"><span class="fill" style="width:${(tally[o] / total) * 100}%"></span></span><span>${tally[o]}</span></div>`).join("")}
        <div class="small muted">${p.status === "open" ? `open · voters: ${esc(p.voters.map(nameOf).join(", ") || "anyone")}` : `closed · winner: ${esc(p.result?.winner || "tie")}`}</div>
        ${p.status === "open" ? `<button class="btn small" data-close-poll="${esc(p.id)}">Close now</button>` : ""}</div>`;
    }).join("") : '<p class="muted small">No polls yet.</p>';
  }
  if (changed("facts", s.facts)) {
    $("#facts").innerHTML = s.facts.length ? s.facts.map((f) => `<div class="fact"><code>${esc(f.key)}</code> = ${esc(f.value)} <span class="muted small">— ${esc(nameOf(f.author))}</span></div>`).join("") : '<p class="muted small">Shared facts appear here.</p>';
  }
}

function toolEnabled(spec) {
  return !spec.requires_setting || ui.snap?.settings[spec.requires_setting];
}

function renderTools() {
  if (!ui.meta) return;
  const html = ui.meta.tool_categories.map((category) => `<div class="tool-cat">${esc(category)}</div>` +
    ui.meta.tools.filter((t) => t.category === category).map((t) => `<button class="tool-item${t.name === ui.tool ? " active" : ""}${toolEnabled(t) ? "" : " disabled"}" data-tool="${esc(t.name)}">${esc(t.name)}${toolEnabled(t) ? "" : " (off)"}</button>`).join("")).join("");
  if (changed("tools", html)) $("#tool-list").innerHTML = html;
}

function showTool(name) {
  ui.tool = name;
  renderTools();
  const spec = ui.meta.tools.find((t) => t.name === name);
  const props = spec.input_schema.properties;
  const required = new Set(spec.input_schema.required);
  const fields = Object.entries(props).map(([key, schema]) => {
    const label = `<label for="tool-${esc(key)}">${esc(key)}${required.has(key) ? " *" : ""}</label>`;
    const hint = `<span class="hint">${esc(schema.description || "")}${schema.type === "array" ? " (comma separated)" : ""}</span>`;
    let control;
    if (schema.enum) control = `<select class="select" id="tool-${esc(key)}" data-arg="${esc(key)}" data-type="string"><option value="">—</option>${schema.enum.map((v) => `<option>${esc(v)}</option>`).join("")}</select>`;
    else if (TEXTAREA_FIELDS.has(key)) control = `<textarea id="tool-${esc(key)}" rows="${key === "content" || key === "body" ? 8 : 3}" data-arg="${esc(key)}" data-type="string"></textarea>`;
    else control = `<input id="tool-${esc(key)}" type="${schema.type === "integer" ? "number" : "text"}" data-arg="${esc(key)}" data-type="${esc(schema.type)}">`;
    return `<div class="field">${label}${control}${hint}</div>`;
  }).join("");
  $("#tool-form").innerHTML = `<h3>${esc(spec.name)}</h3><p class="desc">${esc(spec.description)}</p>
    ${toolEnabled(spec) ? "" : `<p class="warning">Disabled until “${esc(spec.requires_setting)}” is turned on in Settings.</p>`}
    <form id="tool-run">${fields || '<p class="muted small">No arguments.</p>'}<button class="btn primary" type="submit">Run as You</button></form>`;
  if (props.to) $("#tool-to").value = "#general";
  $("#tool-result").hidden = true;
}

// ------------------------------------------------------------------- modals
function openModal(title, body, buttons = []) {
  if ($("#modal").open) $("#modal").close();
  $("#modal-title").textContent = title;
  $("#modal-body").innerHTML = body;
  const foot = $("#modal-foot");
  foot.innerHTML = "";
  for (const button of buttons) {
    const node = document.createElement("button");
    node.type = "button";
    node.className = `btn ${button.cls || ""}`;
    node.textContent = button.label;
    node.addEventListener("click", async () => {
      const keep = await button.onClick?.();
      if (keep !== true) $("#modal").close();
    });
    foot.appendChild(node);
  }
  $("#modal").showModal();
}

function field(id, label, control, hint = "") {
  return `<div class="field"><label for="${id}">${label}</label>${control}${hint ? `<span class="hint">${hint}</span>` : ""}</div>`;
}

function options(values, selected) {
  return values.map((v) => `<option value="${esc(v)}"${v === selected ? " selected" : ""}>${esc(v)}</option>`).join("");
}

function toolChecklist(selected) {
  return `<div class="tool-grid">${ui.meta.tools.map((t) => `<label class="check"><input type="checkbox" data-tool-perm="${esc(t.name)}"${!selected || selected.includes(t.name) ? " checked" : ""}> ${esc(t.name)}</label>`).join("")}</div>`;
}

function agentForm(a) {
  const models = `<datalist id="model-list">${ui.meta.models.map((m) => `<option value="${esc(m)}">`).join("")}</datalist>`;
  return `<div class="grid2">
    ${a.id ? "" : field("f-id", "Id", '<input type="text" id="f-id" placeholder="e.g. orion">', "lowercase letters, digits, - or _")}
    ${field("f-name", "Name", `<input type="text" id="f-name" value="${esc(a.name || "")}">`)}
    ${field("f-role", "Role", `<select class="select" id="f-role">${options(ui.meta.roles, a.role || "custom")}</select>`)}
    ${field("f-brain", "Brain", `<select class="select" id="f-brain">${options(ui.meta.brains, a.brain || "scripted")}</select>`, "scripted = offline playbook · claude = real model via API")}
    ${field("f-model", "Model", `<input type="text" id="f-model" list="model-list" value="${esc(a.model || ui.snap.settings.default_model)}">${models}`)}
    ${field("f-effort", "Effort", `<select class="select" id="f-effort">${options(ui.meta.efforts, a.effort || "medium")}</select>`)}
    ${field("f-color", "Color", `<input type="color" id="f-color" value="${esc(a.color || "#6d4dff")}">`)}
  </div>
  ${field("f-persona", "Persona", `<textarea id="f-persona" rows="2">${esc(a.persona || "")}</textarea>`, "Shapes how a Claude agent behaves.")}
  <div class="field"><label>Tool permissions</label>${toolChecklist(a.tools)}</div>`;
}

function readAgentForm() {
  const checked = $$("[data-tool-perm]").filter((n) => n.checked).map((n) => n.dataset.toolPerm);
  return {
    name: $("#f-name").value.trim(), role: $("#f-role").value, brain: $("#f-brain").value, model: $("#f-model").value.trim(),
    effort: $("#f-effort").value, color: $("#f-color").value, persona: $("#f-persona").value,
    tools: checked.length === ui.meta.tools.length ? null : checked,
  };
}

async function openAgent(id) {
  const a = await api.get(`/api/agent?id=${encodeURIComponent(id)}`).catch((e) => { toast(e.message, true); return null; });
  if (!a) return;
  const stats = Object.entries(a.stats).map(([k, v]) => `<dt>${esc(k.replace(/_/g, " "))}</dt><dd>${Number(v).toLocaleString()}</dd>`).join("");
  const recent = a.recent.slice(-25).reverse().map((e) => `<li><span class="muted small">t${e.tick}</span> ${rich(e.summary)}</li>`).join("");
  const body = `${agentForm(a)}
    <h3>Status</h3><p>${esc(a.status)} ${a.status_detail ? "— " + esc(a.status_detail) : ""}</p>
    <h3>Stats</h3><dl class="stats">${stats}<dt>Claude history messages</dt><dd>${a.history_turns}</dd></dl>
    <h3 style="margin-top:12px">Private memory</h3><pre class="result">${esc(JSON.stringify(a.memory, null, 1))}</pre>
    <h3 style="margin-top:12px">Recent activity</h3><ul class="note-list">${recent || "<li>Nothing yet.</li>"}</ul>`;
  openModal(`${a.name} · ${a.role}`, body, [
    { label: "Remove", cls: "danger", onClick: async () => { if (!confirm(`Remove ${a.name} from the team?`)) return true; await safely(() => api.post("/api/agents", { action: "remove", id }), `${a.name} removed`); } },
    { label: "Nudge", onClick: () => safely(() => api.post("/api/agents", { action: "nudge", id }), `Nudged ${a.name}`) },
    { label: "Message", onClick: () => { selectConversation(`@${id}`); $("#composer-text").focus(); } },
    { label: "Save", cls: "primary", onClick: () => safely(() => api.post("/api/agents", { action: "update", id, changes: readAgentForm() }), "Saved") },
  ]);
}

function openAddAgent() {
  openModal("Add an agent", agentForm({}), [
    { label: "Cancel" },
    { label: "Add", cls: "primary", onClick: async () => {
      const data = readAgentForm();
      data.id = $("#f-id").value.trim() || data.name.toLowerCase().replace(/[^a-z0-9_-]/g, "");
      const ok = await safely(() => api.post("/api/agents", { action: "add", agent: data }), `${data.name} joined`);
      return ok ? undefined : true;
    } },
  ]);
}

function openTask(id) {
  const t = ui.snap.tasks.find((task) => task.id === id);
  if (!t) return;
  const people = [["", "unassigned"], [USER, "You"], ...ui.snap.agents.map((a) => [a.id, a.name])];
  const notes = t.notes.map((n) => `<li><span class="muted small">t${n.tick} ${esc(nameOf(n.author))}:</span> ${rich(n.text)}</li>`).join("");
  const body = `<p class="muted small">${esc(t.id)} · created by ${esc(nameOf(t.created_by))} at tick ${t.created_tick} · depends on ${esc(t.depends_on.join(", ") || "nothing")}</p>
    <h3>${esc(t.title)}</h3><pre class="result">${esc(t.description || "No description.")}</pre>
    ${t.result ? `<h3 style="margin-top:12px">Result</h3><p>${rich(t.result)}</p>` : ""}
    <h3 style="margin-top:12px">Notes</h3><ul class="note-list">${notes || "<li>No notes.</li>"}</ul>
    <div class="grid2" style="margin-top:12px">
      ${field("t-status", "Status", `<select class="select" id="t-status">${options(ui.meta.task_statuses, t.status)}</select>`)}
      ${field("t-assignee", "Assignee", `<select class="select" id="t-assignee">${people.map(([v, l]) => `<option value="${esc(v)}"${(t.assignee || "") === v ? " selected" : ""}>${esc(l)}</option>`).join("")}</select>`)}
    </div>${field("t-note", "Add a note", '<textarea id="t-note" rows="2" placeholder="Visible to every agent"></textarea>')}`;
  openModal(`Task ${t.id}`, body, [
    { label: "Close" },
    { label: "Save", cls: "primary", onClick: () => {
      const args = { task_id: t.id };
      if ($("#t-status").value !== t.status) args.status = $("#t-status").value;
      if ($("#t-assignee").value !== (t.assignee || "")) args.assignee = $("#t-assignee").value;
      if ($("#t-note").value.trim()) args.note = $("#t-note").value.trim();
      if (Object.keys(args).length === 1) return undefined;
      return safely(() => tool("update_task", args), `${t.id} updated`);
    } },
  ]);
}

function openNewTask() {
  const people = [["", "unassigned"], ...ui.snap.agents.map((a) => [a.id, `${a.name} (${a.role})`])];
  openModal("New task", `${field("n-title", "Title", '<input type="text" id="n-title">')}
    ${field("n-desc", "Description", '<textarea id="n-desc" rows="4" placeholder="Project: my_slug&#10;Request: what you want"></textarea>', "Scripted agents read the Project: and Request: lines.")}
    ${field("n-assignee", "Assignee", `<select class="select" id="n-assignee">${people.map(([v, l]) => `<option value="${esc(v)}">${esc(l)}</option>`).join("")}</select>`)}
    ${field("n-deps", "Depends on", '<input type="text" id="n-deps" placeholder="T-1, T-2">')}`, [
    { label: "Cancel" },
    { label: "Create", cls: "primary", onClick: () => {
      const args = { title: $("#n-title").value, description: $("#n-desc").value };
      if ($("#n-assignee").value) args.assignee = $("#n-assignee").value;
      const deps = $("#n-deps").value.split(",").map((d) => d.trim()).filter(Boolean);
      if (deps.length) args.depends_on = deps;
      return safely(() => tool("create_task", args), "Task created");
    } },
  ]);
}

function openSettings() {
  const s = ui.snap.settings;
  const body = `<div class="grid2">
      ${field("s-speed", `Delay between ticks: <span id="s-speed-v">${s.speed_ms}</span> ms`, `<input type="range" id="s-speed" min="0" max="2000" step="50" value="${s.speed_ms}">`)}
      ${field("s-ticks", "Max ticks per run", `<input type="number" id="s-ticks" min="1" max="5000" value="${s.max_ticks_per_run}">`)}
      ${field("s-llm", "Claude call budget", `<input type="number" id="s-llm" min="0" max="5000" value="${s.max_llm_calls}">`, `${s.llm_calls_used} used since reset`)}
      ${field("s-turn", "Tool calls per Claude turn", `<input type="number" id="s-turn" min="1" max="40" value="${s.max_tool_calls_per_turn}">`)}
      ${field("s-model", "Default model for new agents", `<input type="text" id="s-model" list="settings-models" value="${esc(s.default_model)}"><datalist id="settings-models">${ui.meta.models.map((m) => `<option value="${esc(m)}">`).join("")}</datalist>`)}
      ${field("s-key", "Anthropic API key", `<input type="password" id="s-key" autocomplete="off" placeholder="${s.has_api_key ? "a key is set (kept in memory only)" : "uses ANTHROPIC_API_KEY when empty"}">`, "Never saved to disk or exports.")}
    </div>
    <label class="check"><input type="checkbox" id="s-auto"${s.auto_run ? " checked" : ""}> Start running automatically when you send a message</label>
    <label class="check" style="margin-top:8px"><input type="checkbox" id="s-exec"${s.allow_code_execution ? " checked" : ""}> Allow agents to run Python (run_python tool)</label>
    <p class="warning" style="margin-top:8px">run_python executes workspace code on this computer in a temporary folder with a timeout. It is not a security sandbox; enable it only when you trust the agents and their output.</p>
    <h3 style="margin-top:14px">State</h3>
    <p><a class="btn small" href="/api/export" download>Export JSON</a> <button type="button" class="btn small" id="s-import">Import JSON…</button> <button type="button" class="btn small" id="s-clear-key"${s.has_api_key ? "" : " disabled"}>Forget API key</button></p>`;
  openModal("Settings", body, [
    { label: "Cancel" },
    { label: "Save", cls: "primary", onClick: () => {
      const changes = { speed_ms: Number($("#s-speed").value), max_ticks_per_run: Number($("#s-ticks").value), max_llm_calls: Number($("#s-llm").value),
        max_tool_calls_per_turn: Number($("#s-turn").value), default_model: $("#s-model").value.trim(), auto_run: $("#s-auto").checked,
        allow_code_execution: $("#s-exec").checked };
      if ($("#s-key").value.trim()) changes.api_key = $("#s-key").value.trim();
      return safely(() => api.post("/api/settings", changes), "Settings saved");
    } },
  ]);
  $("#s-speed").addEventListener("input", (e) => { $("#s-speed-v").textContent = e.target.value; });
  $("#s-import").addEventListener("click", () => $("#import-file").click());
  $("#s-clear-key").addEventListener("click", () => safely(() => api.post("/api/settings", { api_key: "" }), "API key forgotten").then(() => $("#modal").close()));
}

function openNewFile() {
  openModal("New file", `${field("nf-path", "Path", '<input type="text" id="nf-path" placeholder="notes/ideas.md">')}${field("nf-content", "Content", '<textarea id="nf-content" rows="10"></textarea>')}`, [
    { label: "Cancel" },
    { label: "Create", cls: "primary", onClick: async () => {
      const path = $("#nf-path").value.trim();
      const ok = await safely(() => tool("write_file", { path, content: $("#nf-content").value }), `Saved ${path}`);
      if (ok) { ui.file = ok.result.path; switchTab("files"); }
    } },
  ]);
}

function openAddKnowledge() {
  const sample = "Explain the approach here.\n\n```python module\n\"\"\"Module docstring.\"\"\"\n\n\ndef example(value: int) -> int:\n    \"\"\"Return the value doubled.\"\"\"\n    return value * 2\n```\n";
  openModal("Add knowledge note", `${field("k-title", "Title", '<input type="text" id="k-title">')}
    ${field("k-keywords", "Keywords", '<input type="text" id="k-keywords" placeholder="comma separated; any language">', "A request that contains a keyword finds this note.")}
    ${field("k-body", "Body (Markdown)", `<textarea id="k-body" rows="12">${esc(sample)}</textarea>`, "A ```python module block becomes code the scripted coder can use; ```python tests becomes its tests.")}`, [
    { label: "Cancel" },
    { label: "Add", cls: "primary", onClick: () => safely(() => tool("add_knowledge", { title: $("#k-title").value, body: $("#k-body").value,
      keywords: $("#k-keywords").value.split(",").map((k) => k.trim()).filter(Boolean) }), "Knowledge added").then(() => searchKnowledge()) },
  ]);
}

// ---------------------------------------------------------------- knowledge
async function searchKnowledge() {
  const q = $("#kb-query").value.trim();
  const data = await api.get(`/api/knowledge${q ? `?q=${encodeURIComponent(q)}` : ""}`).catch((e) => { toast(e.message, true); return { results: [] }; });
  $("#kb-results").innerHTML = data.results.length ? data.results.map((r) => `<button class="kb-item${r.id === ui.doc ? " active" : ""}" data-doc="${esc(r.id)}"><b>${esc(r.title)}</b><small>${esc(r.kind)}${r.module ? " · " + esc(r.module) : ""}${r.score ? " · score " + r.score : ""}</small></button>`).join("") : '<p class="muted small" style="padding:0 14px">No matches.</p>';
}

async function showDoc(id) {
  ui.doc = id;
  $$(".kb-item").forEach((n) => n.classList.toggle("active", n.dataset.doc === id));
  const d = await api.get(`/api/knowledge?id=${encodeURIComponent(id)}`).catch((e) => { toast(e.message, true); return null; });
  if (!d) return;
  $("#kb-view").innerHTML = `<div class="file-head"><div><span class="path">${esc(d.title)}</span> <span class="muted small">${esc(d.kind)} · ${esc(d.id)}</span></div><span class="muted small">keywords: ${esc(d.keywords.join(", "))}</span></div><div class="markdown">${markdown(d.body)}</div>`;
}

// ------------------------------------------------------------------ actions
function switchTab(tab) {
  ui.tab = tab;
  $$("#main-tabs button").forEach((b) => b.classList.toggle("active", b.dataset.tab === tab));
  $$(".tab-body").forEach((p) => { p.hidden = p.dataset.pane !== tab; });
  if (tab === "network") { ui.sig.network = null; renderNetwork(); }
  if (tab === "knowledge" && !$("#kb-results").innerHTML) searchKnowledge();
  if (tab === "activity" && $("#follow-activity").checked) { const pane = $("#timeline").parentElement; pane.scrollTop = pane.scrollHeight; }
}

function selectConversation(key) {
  ui.conv = key;
  switchTab("chat");
  ui.sig.messages = null;
  renderConversations();
  renderMessages();
  renderComposerTargets();
}

async function sendMessage(text, to) {
  if (!text.trim()) return;
  const target = to || $("#composer-to").value;
  const ok = await safely(() => api.post("/api/message", { to: target, text }));
  if (!ok) return;
  $("#composer-text").value = "";
  const key = target.startsWith("#") ? target : `@${target}`;
  if (ui.conv !== "*" && ui.conv !== key) selectConversation(key);
}

function wire() {
  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-file],[data-task],[data-agent],[data-nudge],[data-dm],[data-conv],[data-control],[data-suggest],[data-tool],[data-doc],[data-close-poll],[data-file-action],[data-tab],[data-node]");
    if (!target) return;
    const d = target.dataset;
    if (d.nudge) { event.stopPropagation(); safely(() => api.post("/api/agents", { action: "nudge", id: d.nudge }), `Nudged ${nameOf(d.nudge)}`); }
    else if (d.dm) { event.stopPropagation(); selectConversation(`@${d.dm}`); $("#composer-text").focus(); }
    else if (d.agent) openAgent(d.agent);
    else if (d.node && d.node !== USER && !d.node.startsWith("#")) openAgent(d.node);
    else if (d.fileAction) fileAction(d.fileAction);
    else if (d.file) { if ($("#modal").open) $("#modal").close(); ui.file = d.file; ui.editing = false; ui.sig["file-view"] = null; switchTab("files"); renderFiles(); }
    else if (d.task) { if ($("#modal").open) $("#modal").close(); openTask(d.task); }
    else if (d.conv) selectConversation(d.conv);
    else if (d.tab) switchTab(d.tab);
    else if (d.control) control(d.control);
    else if (d.suggest) {
      const coordinator = ui.snap.agents.find((a) => a.role === "coordinator");
      sendMessage(d.suggest, coordinator ? coordinator.id : "#general");
      if (coordinator) selectConversation(`@${coordinator.id}`);
    }
    else if (d.tool) showTool(d.tool);
    else if (d.doc) showDoc(d.doc);
    else if (d.closePoll) safely(() => tool("close_poll", { poll_id: d.closePoll }), `${d.closePoll} closed`);
  });
  $("#composer").addEventListener("submit", (e) => { e.preventDefault(); sendMessage($("#composer-text").value); });
  $("#composer-text").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); sendMessage(e.target.value); }
  });
  $("#add-agent").addEventListener("click", openAddAgent);
  $("#new-task").addEventListener("click", openNewTask);
  $("#new-file").addEventListener("click", openNewFile);
  $("#kb-add").addEventListener("click", openAddKnowledge);
  $("#open-settings").addEventListener("click", openSettings);
  $("#kb-search").addEventListener("submit", (e) => { e.preventDefault(); searchKnowledge(); });
  $("#kb-query").addEventListener("input", () => { clearTimeout(ui.kbTimer); ui.kbTimer = setTimeout(searchKnowledge, 250); });
  $("#filter-type").addEventListener("change", () => renderTimeline(true));
  $("#filter-actor").addEventListener("change", () => renderTimeline(true));
  $("#scenario-select").addEventListener("change", async (e) => {
    const id = e.target.value;
    e.target.value = "";
    if (id && confirm("Loading a scenario replaces the current world. Continue?")) {
      await safely(() => api.post("/api/scenario", { id }), "Scenario loaded");
      await refresh(true);
    }
  });
  $("#import-file").addEventListener("change", async (e) => {
    const file = e.target.files[0];
    e.target.value = "";
    if (!file) return;
    try {
      const state = JSON.parse(await file.text());
      await safely(() => api.post("/api/import", { state }), "State imported");
      $("#modal").close();
      await refresh(true);
    } catch (error) { toast(`Import failed: ${error.message}`, true); }
  });
  document.addEventListener("submit", (e) => {
    if (e.target.id !== "tool-run") return;
    e.preventDefault();
    const args = {};
    for (const input of $$("[data-arg]", e.target)) {
      const raw = input.value;
      if (raw === "") continue;
      const type = input.dataset.type;
      args[input.dataset.arg] = type === "integer" ? Number(raw) : type === "array" ? raw.split(",").map((v) => v.trim()).filter(Boolean) : raw;
    }
    api.post("/api/tool", { name: ui.tool, args }).then((r) => showResult(r, false)).catch((error) => showResult({ error: error.message }, true)).finally(refresh);
  });
}

function showResult(result, bad) {
  const box = $("#tool-result");
  box.hidden = false;
  box.classList.toggle("bad", bad);
  box.textContent = JSON.stringify(result.result ?? result, null, 2);
}

async function control(action) {
  if (action === "reset" && !confirm("Reset clears messages, tasks and files and restores the default team. Continue?")) return;
  await safely(() => api.post("/api/control", { action }));
  if (action === "reset") await refresh(true);
}

async function fileAction(action) {
  const path = ui.file;
  if (action === "preview") { ui.preview = !ui.preview; ui.sig["file-view"] = null; renderFiles(); return; }
  if (action === "delete") {
    if (confirm(`Delete ${path}?`)) await safely(() => tool("delete_file", { path }), `Deleted ${path}`);
    return;
  }
  if (action === "edit") {
    const record = await api.get(`/api/file?path=${encodeURIComponent(path)}`);
    ui.editing = true;
    $("#file-view").innerHTML = `<div class="file-head"><span class="path">${esc(path)}</span><div><button class="btn small" data-file-action="cancel">Cancel</button> <button class="btn small primary" data-file-action="save">Save as You</button></div></div><textarea class="editor" id="editor" spellcheck="false">${esc(record.content)}</textarea>`;
    return;
  }
  if (action === "cancel") { ui.editing = false; ui.sig["file-view"] = null; renderFiles(); return; }
  if (action === "save") {
    const content = $("#editor").value;
    ui.editing = false;
    ui.sig["file-view"] = null;
    await safely(() => tool("write_file", { path, content }), `Saved ${path}`);
  }
}

async function start() {
  wire();
  try {
    ui.meta = await api.get("/api/meta");
    $("#scenario-select").insertAdjacentHTML("beforeend", ui.meta.scenarios.map((s) => `<option value="${esc(s.id)}" title="${esc(s.description)}">${esc(s.name)}</option>`).join(""));
  } catch (error) {
    toast(`Cannot reach the server: ${error.message}`, true);
  }
  loop();
}

start();
