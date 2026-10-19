/**
 * Phase 2 admin page: create, list and revoke device tokens. Styled with the Tahini & Mint
 * tokens (docs/design.md). Served only behind Cloudflare Access.
 */
export const ADMIN_PAGE = /* html */ `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lakhas Admin</title>
<style>
  :root { --bg:#FBF7F0; --surface:#FFFFFF; --ink:#2A2420; --muted:#6B6158; --line:#E6DCCC;
          --primary:#1F7A5A; --on-primary:#FFFFFF; --accent:#B4363F; color-scheme: light; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#171412; --surface:#221E1B; --ink:#F3EDE4; --muted:#A89E93; --line:#332D28;
            --primary:#5CC59B; --on-primary:#0E1F18; --accent:#F07A80; color-scheme: dark; }
  }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 860px; margin: 0 auto; padding: 32px 16px; display: grid; gap: 24px; }
  h1 { margin: 0; font-size: 26px; } h2 { margin: 0 0 12px; font-size: 18px; }
  .card { background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 20px; }
  form { display: flex; gap: 8px; flex-wrap: wrap; }
  input { flex: 1; min-width: 200px; padding: 10px 12px; border: 1px solid var(--line); border-radius: 12px; background: var(--bg); color: var(--ink); font: inherit; }
  button { padding: 10px 16px; border: 0; border-radius: 999px; background: var(--primary); color: var(--on-primary); font: inherit; font-weight: 600; cursor: pointer; }
  button.danger { background: none; color: var(--accent); border: 1px solid var(--line); }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { text-align: start; padding: 8px 6px; border-bottom: 1px solid var(--line); vertical-align: middle; }
  th { color: var(--muted); font-weight: 500; }
  .muted { color: var(--muted); } .revoked { color: var(--muted); text-decoration: line-through; }
  #created { display: none; gap: 16px; grid-template-columns: 180px 1fr; align-items: start; }
  #created svg { width: 180px; height: 180px; background: #fff; border-radius: 12px; }
  code { display: block; word-break: break-all; background: var(--bg); padding: 10px; border-radius: 10px; font-size: 13px; }
  .table-wrap { overflow-x: auto; }
</style>
</head>
<body>
<main>
  <header><h1>لخّص · Lakhas admin</h1><p class="muted">Device access tokens</p></header>

  <section class="card">
    <h2>New device</h2>
    <form id="create">
      <input id="label" name="label" placeholder="Label, e.g. Khaled's iPhone" maxlength="60" required>
      <button type="submit">Create token</button>
    </form>
    <div id="created" class="card" style="margin-top:16px">
      <div id="qr"></div>
      <div>
        <p><strong>Shown once.</strong> Scan the QR code in the app or paste this token:</p>
        <code id="token"></code>
        <p><button type="button" id="copy">Copy token</button></p>
      </div>
    </div>
  </section>

  <section class="card">
    <h2>Devices</h2>
    <div class="table-wrap"><table>
      <thead><tr><th>Label</th><th>Token ID</th><th>Created</th><th>Last seen</th><th></th></tr></thead>
      <tbody id="rows"><tr><td colspan="5" class="muted">Loading…</td></tr></tbody>
    </table></div>
  </section>
</main>
<script>
const fmt = (ms) => ms ? new Date(ms).toLocaleString() : "—";
const esc = (s) => String(s).replace(/[&<>"']/g, (ch) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));

async function load() {
  const res = await fetch("/admin/api/devices");
  const { items } = await res.json();
  document.getElementById("rows").innerHTML = items.length ? items.map((d) => \`
    <tr class="\${d.status === "revoked" ? "revoked" : ""}">
      <td>\${esc(d.label)}</td><td><small>\${esc(d.token_id)}</small></td>
      <td>\${fmt(d.created_at)}</td><td>\${fmt(d.last_seen_at)}</td>
      <td>\${d.status === "active" ? \`<button class="danger" data-revoke="\${esc(d.token_id)}">Revoke</button>\` : "revoked"}</td>
    </tr>\`).join("") : '<tr><td colspan="5" class="muted">No devices yet.</td></tr>';
}

document.getElementById("create").addEventListener("submit", async (e) => {
  e.preventDefault();
  const label = document.getElementById("label").value;
  const res = await fetch("/admin/api/devices", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ label }) });
  if (!res.ok) { alert("Couldn't create the token."); return; }
  const data = await res.json();
  document.getElementById("qr").innerHTML = data.qrSvg;
  document.getElementById("token").textContent = data.token;
  document.getElementById("created").style.display = "grid";
  document.getElementById("label").value = "";
  load();
});

document.getElementById("copy").addEventListener("click", () => {
  navigator.clipboard.writeText(document.getElementById("token").textContent);
});

document.getElementById("rows").addEventListener("click", async (e) => {
  const id = e.target.dataset && e.target.dataset.revoke;
  if (!id || !confirm("Revoke this device? The app will ask for a new token.")) return;
  await fetch("/admin/api/devices/" + encodeURIComponent(id) + "/revoke", { method: "POST" });
  load();
});

load();
</script>
</body>
</html>`;
