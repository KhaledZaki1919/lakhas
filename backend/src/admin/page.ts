/** The admin panel (ADR-027 §7): one HTML page + one script, served behind Cloudflare Access. */

export const ADMIN_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lakhas admin</title>
<style>
:root { color-scheme: light dark; --bg: #FBF7F0; --surface: #FFFFFF; --ink: #2A2420; --muted: #6B6158;
  --line: #E6DCCC; --primary: #1F7A5A; --on-primary: #FFFFFF; --accent: #B4363F; }
@media (prefers-color-scheme: dark) { :root { --bg: #171412; --surface: #221E1B; --ink: #F3EDE4;
  --muted: #A89E93; --line: #332D28; --primary: #5CC59B; --on-primary: #0E1F18; --accent: #F07A80; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 15px/1.5 -apple-system, system-ui, sans-serif; }
header { display: flex; gap: 16px; align-items: center; padding: 12px 16px; background: var(--surface);
  border-bottom: 1px solid var(--line); position: sticky; top: 0; flex-wrap: wrap; }
header h1 { font-size: 18px; margin: 0; color: var(--primary); }
nav button { background: none; border: 0; color: var(--muted); font: inherit; padding: 6px 10px; cursor: pointer; border-radius: 14px; }
nav button[aria-current="page"] { background: var(--primary); color: var(--on-primary); }
main { max-width: 1000px; margin: 0 auto; padding: 16px; }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 20px; padding: 16px; margin-bottom: 16px; }
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; }
.stat b { display: block; font-size: 24px; font-variant-numeric: tabular-nums; }
.stat span { color: var(--muted); font-size: 13px; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: start; padding: 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { color: var(--muted); font-weight: 600; font-size: 13px; }
button.action { border: 1px solid var(--line); background: var(--surface); color: var(--ink); border-radius: 14px; padding: 4px 12px; cursor: pointer; font: inherit; }
button.primary { background: var(--primary); color: var(--on-primary); border-color: var(--primary); }
button.danger { color: var(--accent); }
input { font: inherit; padding: 6px 10px; border: 1px solid var(--line); border-radius: 14px; background: var(--bg); color: var(--ink); }
.muted { color: var(--muted); } .code { font: 600 20px ui-monospace, monospace; letter-spacing: 1px; }
.row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
#toast { position: fixed; inset-inline-end: 16px; bottom: 16px; background: var(--ink); color: var(--bg); padding: 8px 14px; border-radius: 20px; display: none; }
</style>
</head>
<body>
<header>
  <h1>لخّص · Lakhas admin</h1>
  <nav aria-label="Sections">
    <button data-view="overview">Overview</button>
    <button data-view="users">Users</button>
    <button data-view="invites">Invites</button>
    <button data-view="audit">Audit log</button>
    <button data-view="abuse">Abuse</button>
  </nav>
  <span class="muted" id="who"></span>
</header>
<main id="main" aria-live="polite"></main>
<div id="toast" role="status"></div>
<script src="/app.js"></script>
</body>
</html>`;

export const ADMIN_JS = `"use strict";
const main = document.getElementById("main");
const toast = document.getElementById("toast");

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "onclick") node.addEventListener("click", v);
    else if (v !== null && v !== undefined) node.setAttribute(k, v);
  }
  for (const child of children.flat()) {
    node.append(child instanceof Node ? child : document.createTextNode(String(child ?? "")));
  }
  return node;
}
function when(ms) { return ms ? new Date(ms).toLocaleString() : "—"; }
function say(text) { toast.textContent = text; toast.style.display = "block"; setTimeout(() => (toast.style.display = "none"), 2500); }

async function api(path, options = {}) {
  const res = await fetch("/api" + path, {
    ...options,
    headers: { "Content-Type": "application/json", "X-Lakhas-Admin": "1", ...(options.headers || {}) },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data.error && data.error.code) || res.statusText);
  return data;
}

const views = {
  async overview() {
    const o = await api("/overview");
    const stat = (value, label) => el("div", { class: "stat" }, el("b", {}, value), el("span", {}, label));
    return [
      el("div", { class: "card stats" },
        stat(o.users, "users"), stat(o.disabled, "disabled"), stat(o.devices, "signed-in devices"),
        stat(o.storage.mainDbBytes != null ? (o.storage.mainDbBytes / 1e6).toFixed(2) + " MB" : "—", "main D1 size (500 MB free)"),
        stat(o.today.kvWrites + " / " + o.today.kvWritesLimit, "KV writes today (guard)")),
      el("div", { class: "card" }, el("h2", {}, "Current invite code"),
        o.invite ? el("p", { class: "code" }, o.invite.code) : el("p", { class: "muted" }, "No active invite — nobody can sign up."),
        o.invite ? el("p", { class: "muted" }, "Used " + o.invite.uses + (o.invite.max_uses ? " / " + o.invite.max_uses : "") + " · expires " + when(o.invite.expires_at)) : ""),
    ];
  },

  async users() {
    const search = el("input", { type: "search", placeholder: "Email starts with…", "aria-label": "Search users" });
    const table = el("div");
    async function load() {
      const { users } = await api("/users?q=" + encodeURIComponent(search.value));
      table.replaceChildren(el("table", {},
        el("thead", {}, el("tr", {}, ["Email", "Status", "Devices", "Last seen", "Joined", ""].map((h) => el("th", {}, h)))),
        el("tbody", {}, users.map((u) => el("tr", {},
          el("td", {}, u.email), el("td", {}, u.status), el("td", {}, u.devices),
          el("td", {}, when(u.last_seen_at)), el("td", {}, when(u.created_at)),
          el("td", { class: "row" },
            el("button", { class: "action", onclick: () => showDevices(u) }, "Devices"),
            u.status === "active"
              ? el("button", { class: "action danger", onclick: () => setStatus(u, "disabled") }, "Disable")
              : el("button", { class: "action", onclick: () => setStatus(u, "active") }, "Enable")))))));
    }
    async function setStatus(u, status) {
      if (status === "disabled" && !confirm("Disable " + u.email + "? All their devices are signed out.")) return;
      await api("/users/" + encodeURIComponent(u.id) + "/status", { method: "POST", body: JSON.stringify({ status }) });
      say(status === "disabled" ? "Disabled" : "Enabled"); load();
    }
    async function showDevices(u) {
      const { devices } = await api("/users/" + encodeURIComponent(u.id));
      table.replaceChildren(el("p", {}, el("button", { class: "action", onclick: load }, "← Users"), " ", u.email),
        el("table", {}, el("thead", {}, el("tr", {}, ["Device", "App", "Status", "Last seen", ""].map((h) => el("th", {}, h)))),
          el("tbody", {}, devices.map((d) => el("tr", {},
            el("td", {}, d.label), el("td", {}, d.app_version || "—"), el("td", {}, d.status), el("td", {}, when(d.last_seen_at)),
            el("td", {}, d.status === "active" ? el("button", { class: "action danger", onclick: async () => {
              await api("/devices/" + encodeURIComponent(d.id) + "/revoke", { method: "POST", body: "{}" }); say("Signed out"); showDevices(u);
            } }, "Sign out") : ""))))));
    }
    search.addEventListener("input", () => load());
    await load();
    return [el("div", { class: "card" }, search), el("div", { class: "card" }, table)];
  },

  async invites() {
    const { invites } = await api("/invites");
    const code = el("input", { placeholder: "Custom code (optional)", "aria-label": "Custom code" });
    const maxUses = el("input", { type: "number", min: "1", placeholder: "Max uses", "aria-label": "Max uses" });
    const days = el("input", { type: "number", min: "1", placeholder: "Expires in days", "aria-label": "Expires in days" });
    async function create() {
      const payload = {};
      if (code.value.trim()) payload.code = code.value.trim();
      if (maxUses.value) payload.maxUses = Number(maxUses.value);
      if (days.value) payload.expiresInDays = Number(days.value);
      const made = await api("/invites", { method: "POST", body: JSON.stringify(payload) });
      say("New code: " + made.code); render("invites");
    }
    async function stop() {
      if (!confirm("Stop all invite codes? Nobody can sign up until you make a new one.")) return;
      await api("/invites/deactivate", { method: "POST", body: "{}" }); say("Invites stopped"); render("invites");
    }
    return [
      el("div", { class: "card" }, el("h2", {}, "New invite code"), el("p", { class: "muted" }, "Making a new code stops the old one."),
        el("div", { class: "row" }, code, maxUses, days,
          el("button", { class: "action primary", onclick: create }, "Create"),
          el("button", { class: "action danger", onclick: stop }, "Stop all"))),
      el("div", { class: "card" }, el("table", {},
        el("thead", {}, el("tr", {}, ["Code", "Active", "Uses", "Expires", "Created"].map((h) => el("th", {}, h)))),
        el("tbody", {}, invites.map((i) => el("tr", {},
          el("td", { class: "code" }, i.code), el("td", {}, i.active ? "yes" : "no"),
          el("td", {}, i.uses + (i.max_uses ? " / " + i.max_uses : "")), el("td", {}, when(i.expires_at)), el("td", {}, when(i.created_at))))))),
    ];
  },

  async audit() {
    const { entries } = await api("/audit");
    return [el("div", { class: "card" }, el("table", {},
      el("thead", {}, el("tr", {}, ["When", "Who", "Action", "Target"].map((h) => el("th", {}, h)))),
      el("tbody", {}, entries.map((e) => el("tr", {}, el("td", {}, when(e.created_at)), el("td", {}, e.actor), el("td", {}, e.action), el("td", { class: "muted" }, e.target || "")))))) ];
  },

  async abuse() {
    const { events } = await api("/abuse");
    return [el("div", { class: "card" }, el("table", {},
      el("thead", {}, el("tr", {}, ["When", "Kind", "IP (hashed)", "User"].map((h) => el("th", {}, h)))),
      el("tbody", {}, events.map((e) => el("tr", {}, el("td", {}, when(e.created_at)), el("td", {}, e.kind), el("td", { class: "muted" }, e.ip_hash || ""), el("td", { class: "muted" }, e.user_id || "")))))) ];
  },
};

async function render(name) {
  document.querySelectorAll("nav button").forEach((b) => b.setAttribute("aria-current", b.dataset.view === name ? "page" : "false"));
  main.replaceChildren(el("p", { class: "muted" }, "Loading…"));
  try { main.replaceChildren(...(await views[name]())); }
  catch (err) { main.replaceChildren(el("div", { class: "card" }, "Couldn't load: " + err.message)); }
  history.replaceState(null, "", "#" + name);
}

document.querySelectorAll("nav button").forEach((b) => b.addEventListener("click", () => render(b.dataset.view)));
api("/me").then((me) => (document.getElementById("who").textContent = me.email)).catch(() => {});
render(views[location.hash.slice(1)] ? location.hash.slice(1) : "overview");
`;
