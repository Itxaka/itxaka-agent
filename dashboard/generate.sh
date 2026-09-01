#!/usr/bin/env bash
# Generate a self-contained HTML dashboard from the audit ledger.
#
# Usage: dashboard/generate.sh [db_path] [out_path]
# Default: dashboard/generate.sh workspace/.state/audit.sqlite dashboard/index.html
#
# No server required, no build step — open the resulting file in a browser.
# One tiny inline script drives the Artifacts filter + pagination; everything
# else is CSS-only (radio-input tabs, <details> accordions).

set -euo pipefail

DB="${1:-workspace/.state/audit.sqlite}"
OUT="${2:-dashboard/index.html}"

if [ ! -f "$DB" ]; then
  echo "audit DB not found at $DB" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

now_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
abs_db="$(readlink -f "$DB")"

# --- SQL helpers -------------------------------------------------------------
#
# The queries emit sentinel tokens that sqlite3 -html leaves alone; sed
# rehydrates them after the HTML escape pass. Two sentinels exist:
#
#   %PILL:<class>:<label>%   -> <span class="pill <class>"><label></span>
#   %MUTED:<text>%           -> <span class="muted"><text></span>
#   %SLOT:<seq>:<slot_id>%   -> <span class="pill mono" title="<slot_id>">#<seq></span>
#
# Neither sentinel occurs in real data.

# Map a state string (outcome / phase / verdict / mode) to a pill sentinel,
# or a muted em dash when the column is NULL or empty.
pill_case() {
  local col="$1"
  cat <<SQL
CASE
  WHEN COALESCE($col,'')='' THEN '%MUTED:—%'
  WHEN $col='dry-run' THEN '%PILL:blue:dry-run%'
  WHEN $col IN ('live','idle') THEN '%PILL:neutral:'||$col||'%'
  WHEN $col IN ('done','approve') THEN '%PILL:ok:'||$col||'%'
  WHEN $col IN ('awaiting-author','changes-requested','in-flight','coding','testing','docs','reviewing') THEN '%PILL:warn:'||$col||'%'
  WHEN $col IN ('escalated','error') THEN '%PILL:bad:'||$col||'%'
  ELSE '%PILL:neutral:'||$col||'%'
END
SQL
}

# Replace null/empty text cells with a muted em dash sentinel.
dash_text() {
  local col="$1"
  echo "CASE WHEN COALESCE($col,'')='' THEN '%MUTED:—%' ELSE $col END"
}

# Same for numeric columns (0 is a real value, only NULL becomes a dash).
dash_num() {
  local col="$1"
  echo "CASE WHEN $col IS NULL THEN '%MUTED:—%' ELSE CAST($col AS TEXT) END"
}

# Slot name pill from seq + slot_id. Falls back to a short slot_id when seq
# is somehow NULL (row inserted by an old manager, not yet backfilled).
slot_name() {
  local seq_col="$1" id_col="$2"
  cat <<SQL
CASE
  WHEN $seq_col IS NULL
    THEN '%PILL:mono:'||substr($id_col,1,17)||'%'
  ELSE '%SLOT:'||printf('%04d', $seq_col)||':'||$id_col||'%'
END
SQL
}

# Emit a section: title + a table produced by a sqlite3 -html query, with
# sentinels rehydrated.
section() {
  local title="$1" query="$2"
  echo "<section>"
  echo "<h2>$title</h2>"
  local html
  html="$(sqlite3 -html "$DB" "$query" 2>/dev/null || echo '')"
  if [ -z "$html" ]; then
    echo '<p class="empty">no rows</p>'
  else
    printf '<table>%s</table>\n' "$html" | rehydrate
  fi
  echo "</section>"
}

# The single sed pass that turns sentinels back into HTML. Kept here so every
# emitter routes through the same escaping.
rehydrate() {
  sed -E \
    -e 's|%PILL:([a-z0-9_-]+):([^%]*)%|<span class="pill \1">\2</span>|g' \
    -e 's|%MUTED:([^%]*)%|<span class="muted">\1</span>|g' \
    -e 's|%SLOT:([0-9]+):([^%]+)%|<span class="pill mono" title="\2">#\1</span>|g'
}

# Escape HTML for inline text values (used inside <pre> for journal previews).
htmlescape() {
  python3 -c 'import html,sys;sys.stdout.write(html.escape(sys.stdin.read()))'
}

# --- write output ------------------------------------------------------------

{
cat <<HEAD
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>kairos-triage-agent dashboard</title>
<style>
:root{
  --bg:#fafafa; --fg:#1c1c1c; --muted:#6b6b6b; --line:#e4e4e4;
  --panel:#fff; --accent:#0b5cad;
  --pill-ok:#d5e8d4;    --pill-ok-fg:#245825;
  --pill-warn:#fff2cc;  --pill-warn-fg:#7a5900;
  --pill-bad:#f8cecc;   --pill-bad-fg:#6f1a1a;
  --pill-blue:#e6f0ff;  --pill-blue-fg:#003366;
  --pill-neutral:#e8e8e8; --pill-neutral-fg:#3a3a3a;
  --tab-bar:#eee; --tab-active:#fff;
}
@media (prefers-color-scheme:dark){
  :root{ --bg:#111; --fg:#eaeaea; --muted:#9a9a9a; --line:#2b2b2b; --panel:#181818;
    --accent:#5aa8ff;
    --pill-ok:#1e3a1e;    --pill-ok-fg:#a2d29e;
    --pill-warn:#3a2f0a;  --pill-warn-fg:#e6c060;
    --pill-bad:#3a1414;   --pill-bad-fg:#e69a94;
    --pill-blue:#0f2440;  --pill-blue-fg:#8fb8ea;
    --pill-neutral:#2a2a2a; --pill-neutral-fg:#bfbfbf;
    --tab-bar:#1c1c1c; --tab-active:#242424; }
}
*{box-sizing:border-box}
body{background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
  margin:0;padding:24px 32px;max-width:1400px;margin:0 auto}
header{margin-bottom:20px}
h1{margin:0;font-size:22px}
.meta{color:var(--muted);font-size:12px;margin-top:4px}
h2{font-size:15px;margin:28px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--line);letter-spacing:.02em;text-transform:uppercase;color:var(--muted)}
section{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px 18px;margin-bottom:16px}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{background:transparent;color:var(--muted);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.03em}
tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(127,127,127,.06)}
code,kbd,pre{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px}
code{background:rgba(127,127,127,.12);padding:1px 5px;border-radius:3px}
pre{background:#0b0b0b;color:#e8e8e8;padding:12px 14px;border-radius:6px;overflow-x:auto;white-space:pre-wrap;line-height:1.4;margin:6px 0}
details{margin:8px 0;padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:rgba(127,127,127,.04)}
details[open]{background:rgba(127,127,127,.06)}
summary{cursor:pointer;font-weight:600;font-size:13px}
summary .small{font-weight:400;color:var(--muted);margin-left:8px}
.muted{color:var(--muted)}
.pill{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;letter-spacing:.02em;line-height:1.5}
.pill.ok      {background:var(--pill-ok);      color:var(--pill-ok-fg)}
.pill.warn    {background:var(--pill-warn);    color:var(--pill-warn-fg)}
.pill.bad     {background:var(--pill-bad);     color:var(--pill-bad-fg)}
.pill.blue    {background:var(--pill-blue);    color:var(--pill-blue-fg)}
.pill.neutral {background:var(--pill-neutral); color:var(--pill-neutral-fg)}
.pill.mono    {background:var(--pill-neutral); color:var(--pill-neutral-fg);
               font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-weight:500}
.stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px;margin-top:6px}
.stat{background:rgba(127,127,127,.06);padding:12px 14px;border-radius:6px}
.stat .n{font-size:22px;font-weight:600;color:var(--accent)}
.stat .k{font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}
.empty{color:var(--muted);font-style:italic;margin:6px 0 0}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}

/* CSS-only radio-input tabs. Inputs are hidden; the labels are the tab bar;
   the ~ selector on each :checked input reveals its matching panel. */
.tabs{margin-top:18px}
.tabs > input[type=radio]{position:absolute;opacity:0;pointer-events:none}
.tabbar{display:flex;gap:2px;border-bottom:1px solid var(--line);margin-bottom:14px;flex-wrap:wrap}
.tabbar label{padding:8px 16px;cursor:pointer;color:var(--muted);border:1px solid transparent;border-bottom:none;border-radius:6px 6px 0 0;font-weight:600;font-size:13px;letter-spacing:.02em}
.tabbar label:hover{color:var(--fg)}
.tabs > .panel{display:none}
#tab-slots:checked     ~ .tabbar label[for=tab-slots],
#tab-tickets:checked   ~ .tabbar label[for=tab-tickets],
#tab-costs:checked     ~ .tabbar label[for=tab-costs],
#tab-artifacts:checked ~ .tabbar label[for=tab-artifacts]{
  color:var(--fg);background:var(--tab-active);border-color:var(--line)}
#tab-slots:checked     ~ #panel-slots,
#tab-tickets:checked   ~ #panel-tickets,
#tab-costs:checked     ~ #panel-costs,
#tab-artifacts:checked ~ #panel-artifacts{display:block}

/* Artifacts filter/pagination controls. */
.artctl{display:flex;gap:10px;align-items:center;margin-bottom:10px;flex-wrap:wrap}
.artctl input[type=text]{flex:1;min-width:200px;padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:var(--panel);color:var(--fg);font:inherit}
.artctl button{padding:6px 12px;border:1px solid var(--line);border-radius:6px;background:var(--panel);color:var(--fg);cursor:pointer;font:inherit}
.artctl button:disabled{opacity:.4;cursor:not-allowed}
.artctl .pageinfo{color:var(--muted);font-size:12px}
</style>
</head><body>

<header>
  <h1>kairos-triage-agent — dashboard</h1>
  <div class="meta">DB <code>$abs_db</code> — generated $now_utc</div>
</header>
HEAD

# ---- overview stats (always visible) ---------------------------------------
echo "<section><h2>Overview</h2><div class=stat-grid>"
sqlite3 "$DB" <<'SQL' | while IFS='|' read -r k v; do
SELECT 'slots',              (SELECT COUNT(*) FROM slots);
SELECT 'tickets touched',    (SELECT COUNT(*) FROM tickets);
SELECT 'approvals',          (SELECT COUNT(*) FROM verdicts WHERE verdict='approve');
SELECT 'changes requested',  (SELECT COUNT(*) FROM verdicts WHERE verdict='changes-requested');
SELECT 'escalations',        (SELECT COUNT(*) FROM slots WHERE outcome='escalated');
SELECT 'total tokens',       (SELECT COALESCE(SUM(tokens),0) FROM costs);
SELECT 'total usd',          printf('$%.2f',(SELECT COALESCE(SUM(usd),0.0) FROM costs));
SELECT 'gated calls',        (SELECT COUNT(*) FROM gated_calls);
SELECT 'artifacts',          (SELECT COUNT(*) FROM artifacts);
SELECT 'worker journals',    (SELECT COUNT(*) FROM worker_reports WHERE journal IS NOT NULL);
SQL
  printf '<div class="stat"><div class="n">%s</div><div class="k">%s</div></div>' "$v" "$k"
done
echo "</div></section>"

# ---- tab bar + panels -------------------------------------------------------
cat <<'TABS_OPEN'
<div class="tabs">
  <input type="radio" name="tab" id="tab-slots" checked>
  <input type="radio" name="tab" id="tab-tickets">
  <input type="radio" name="tab" id="tab-costs">
  <input type="radio" name="tab" id="tab-artifacts">
  <div class="tabbar">
    <label for="tab-slots">Slots</label>
    <label for="tab-tickets">Tickets</label>
    <label for="tab-costs">Costs</label>
    <label for="tab-artifacts">Artifacts</label>
  </div>
TABS_OPEN

# ============================================================================
# Slots panel
# ============================================================================
echo '<div class="panel" id="panel-slots">'

section "Recent slots" "
SELECT
  $(slot_name "seq" "slot_id")                                                AS slot,
  $(dash_text "ticket_ref")                                                   AS ticket,
  CASE WHEN dry_run=1 THEN '%PILL:blue:dry-run%' ELSE '%PILL:neutral:live%' END AS mode,
  $(pill_case "outcome")                                                       AS outcome,
  $(dash_text "entry_reason")                                                  AS reason,
  $(dash_num  "gated_calls")                                                   AS gated,
  $(dash_num  "envelope_writes")                                               AS envwr,
  CASE WHEN wall_ms IS NULL THEN '%MUTED:—%' ELSE printf('%.1fs', wall_ms/1000.0) END AS wall
FROM slots
ORDER BY started_at DESC
LIMIT 100"

# per-slot detail — each closed by default; the user opens what they want
echo '<section><h2>Slot detail</h2>'
sqlite3 -separator $'\x1f' "$DB" "SELECT slot_id, COALESCE(seq,0), COALESCE(ticket_ref,''), COALESCE(outcome,''), started_at FROM slots ORDER BY started_at DESC LIMIT 50" \
  | while IFS=$'\x1f' read -r sid seq tick outc started; do
      if [ "$seq" != "0" ]; then
        name="$(printf '#%04d' "$seq")"
      else
        name="${sid:0:17}"
      fi
      ticket_html="$tick"; [ -z "$ticket_html" ] && ticket_html='<span class="muted">—</span>'
      if [ -z "$outc" ]; then
        outc_html='<span class="muted">—</span>'
      else
        case "$outc" in
          done|approve)                                                             cls=ok ;;
          awaiting-author|changes-requested|in-flight|coding|testing|docs|reviewing) cls=warn ;;
          escalated|error)                                                          cls=bad ;;
          live|idle)                                                                cls=neutral ;;
          dry-run)                                                                  cls=blue ;;
          *)                                                                        cls=neutral ;;
        esac
        outc_html="<span class=\"pill ${cls}\">${outc}</span>"
      fi
      echo "<details>"
      echo "<summary><span class=\"pill mono\" title=\"${sid}\">${name}</span> <code>${ticket_html}</code> ${outc_html} <span class=\"small\">${started}</span></summary>"
      echo "<h3 style=\"font-size:13px;margin:10px 0 4px;color:var(--muted)\">Events</h3>"
      ev="$(sqlite3 -html "$DB" "
        SELECT ts,
               $(dash_text "phase_before") AS 'phase before',
               $(dash_text "phase_after")  AS 'phase after',
               $(dash_text "role")         AS role,
               action,
               $(dash_num  "tokens")       AS tokens,
               $(dash_text "note")         AS note
        FROM events WHERE slot_id='$sid' ORDER BY event_id")"
      if [ -n "$ev" ]; then
        printf '<table>%s</table>\n' "$ev" | rehydrate
      else
        echo '<p class="empty">no events</p>'
      fi

      echo "<h3 style=\"font-size:13px;margin:14px 0 4px;color:var(--muted)\">Worker journals</h3>"
      sqlite3 -separator $'\x1f' "$DB" \
        "SELECT report_id, role, round, COALESCE(journal_path,''), COALESCE(LENGTH(journal),0)
         FROM worker_reports WHERE slot_id='$sid' ORDER BY report_id" \
        | while IFS=$'\x1f' read -r rid role round jpath jlen; do
            jpath_html="$jpath"; [ -z "$jpath_html" ] && jpath_html='<span class="muted">—</span>' || jpath_html="<code>$jpath_html</code>"
            echo "<details><summary>$role — round $round <span class=small>($jlen bytes, $jpath_html)</span></summary>"
            if [ "$jlen" = "0" ]; then
              echo '<p class="empty">no journal written</p>'
            else
              echo "<pre>"
              sqlite3 "$DB" "SELECT COALESCE(journal,'') FROM worker_reports WHERE report_id=$rid" | htmlescape
              echo "</pre>"
            fi
            echo "</details>"
          done

      echo "<h3 style=\"font-size:13px;margin:14px 0 4px;color:var(--muted)\">Gated calls</h3>"
      gc="$(sqlite3 -html "$DB" "SELECT ts, command FROM gated_calls WHERE slot_id='$sid' ORDER BY gated_id")"
      if [ -n "$gc" ]; then
        printf '<table>%s</table>\n' "$gc" | rehydrate
      else
        echo '<p class="empty">none</p>'
      fi

      echo "</details>"
    done
echo '</section>'

echo '</div>' # /panel-slots

# ============================================================================
# Tickets panel
# ============================================================================
echo '<div class="panel" id="panel-tickets">'

section "Tickets touched" "
SELECT
  ticket_ref,
  kind,
  $(dash_text "author") AS author,
  CASE WHEN third_party=1 THEN '%PILL:warn:third-party%'
       WHEN third_party=0 THEN '%PILL:neutral:fleet%'
       ELSE '%MUTED:—%' END        AS third_party,
  $(pill_case "terminal_phase")    AS last_phase,
  first_seen_at,
  last_seen_at
FROM tickets
ORDER BY last_seen_at DESC"

section "Reviewer verdicts" "
SELECT
  $(slot_name "s.seq" "v.slot_id")           AS slot,
  v.ticket_ref                                AS ticket,
  v.round                                     AS round,
  $(pill_case "v.verdict")                    AS verdict,
  v.comment_count                             AS comments,
  v.ts                                        AS ts
FROM verdicts v LEFT JOIN slots s ON s.slot_id=v.slot_id
ORDER BY v.ts DESC"

# By-ticket cards — each ticket is a closed <details>
echo '<section><h2>By ticket</h2>'
sqlite3 -separator $'\x1f' "$DB" "
  SELECT t.ticket_ref,
         COALESCE(t.kind,''),
         COALESCE(t.author,''),
         CASE WHEN t.third_party=1 THEN 'third-party' ELSE 'fleet' END,
         COALESCE(t.terminal_phase,'')
  FROM tickets t
  ORDER BY t.last_seen_at DESC" \
  | while IFS=$'\x1f' read -r tref kind author party phase; do
      author_html="$author"; [ -z "$author_html" ] && author_html='<span class="muted">—</span>'
      kind_html="$kind";     [ -z "$kind_html" ]   && kind_html='<span class="muted">—</span>'
      if [ -z "$phase" ]; then
        phase_html='<span class="muted">—</span>'
      else
        case "$phase" in
          done|approve)                                                             pcls=ok ;;
          awaiting-author|changes-requested|in-flight|coding|testing|docs|reviewing) pcls=warn ;;
          escalated|error)                                                          pcls=bad ;;
          *)                                                                        pcls=neutral ;;
        esac
        phase_html="<span class=\"pill ${pcls}\">${phase}</span>"
      fi

      echo "<details>"
      echo "<summary><code>${tref}</code> <span class=\"small\">${kind_html} / ${author_html} / ${party} / ${phase_html}</span></summary>"

      echo "<h3 style=\"font-size:13px;margin:12px 0 4px;color:var(--muted)\">Latest reviewer conclusion</h3>"
      rid="$(sqlite3 "$DB" "SELECT report_id FROM worker_reports WHERE ticket_ref='$tref' AND role='reviewer' ORDER BY report_id DESC LIMIT 1")"
      if [ -n "$rid" ]; then
        echo "<pre>"
        sqlite3 "$DB" "SELECT COALESCE(return_text,'(no return text)') FROM worker_reports WHERE report_id=$rid" | htmlescape
        echo "</pre>"
      else
        echo '<p class="empty">no reviewer report yet</p>'
      fi

      echo "<h3 style=\"font-size:13px;margin:12px 0 4px;color:var(--muted)\">Comments</h3>"
      cmts="$(sqlite3 -html "$DB" "
        SELECT round AS r,
               role,
               $(dash_text "file")       AS file,
               $(dash_num  "line")       AS line,
               problem,
               $(dash_text "suggestion") AS suggestion
        FROM comments WHERE ticket_ref='$tref' ORDER BY round, comment_id")"
      if [ -n "$cmts" ]; then
        printf '<table>%s</table>\n' "$cmts" | rehydrate
      else
        echo '<p class="empty">no comments on record</p>'
      fi

      echo "<h3 style=\"font-size:13px;margin:12px 0 4px;color:var(--muted)\">Reviewer journal</h3>"
      if [ -n "$rid" ]; then
        jlen="$(sqlite3 "$DB" "SELECT COALESCE(LENGTH(journal),0) FROM worker_reports WHERE report_id=$rid")"
        if [ "$jlen" != "0" ]; then
          echo "<details><summary>show journal <span class=\"small\">(${jlen} bytes)</span></summary>"
          echo "<pre>"
          sqlite3 "$DB" "SELECT journal FROM worker_reports WHERE report_id=$rid" | htmlescape
          echo "</pre>"
          echo "</details>"
        else
          echo '<p class="empty">journal empty</p>'
        fi
      fi

      echo "</details>"
    done
echo '</section>'

echo '</div>' # /panel-tickets

# ============================================================================
# Costs panel
# ============================================================================
echo '<div class="panel" id="panel-costs">'

section "Cost per slot" "
SELECT
  $(slot_name "s.seq" "c.slot_id")     AS slot,
  c.ticket_ref                          AS ticket,
  c.role                                AS role,
  $(dash_num "c.tokens")                AS tokens,
  printf('\$%.4f', c.usd)               AS usd,
  c.ts                                  AS ts
FROM costs c LEFT JOIN slots s ON s.slot_id=c.slot_id
ORDER BY c.ts DESC
LIMIT 200"

echo '</div>' # /panel-costs

# ============================================================================
# Artifacts panel (paginated + filter)
# ============================================================================
echo '<div class="panel" id="panel-artifacts">'
echo '<section><h2>Artifacts produced</h2>'
cat <<'ARTCTL'
<div class="artctl">
  <input type="text" id="art-filter" placeholder="filter by slot / ticket / kind / ref…" autocomplete="off">
  <button id="art-prev" type="button">prev</button>
  <span class="pageinfo" id="art-page">1/1</span>
  <button id="art-next" type="button">next</button>
</div>
ARTCTL

art_html="$(sqlite3 -html "$DB" "
SELECT
  $(slot_name "s.seq" "a.slot_id") AS slot,
  a.ticket_ref                      AS ticket,
  a.kind                            AS kind,
  a.ref                             AS ref,
  $(dash_text "a.note")             AS note,
  a.ts                              AS ts
FROM artifacts a LEFT JOIN slots s ON s.slot_id=a.slot_id
ORDER BY a.artifact_id DESC")"
if [ -n "$art_html" ]; then
  printf '<table id="art-table">%s</table>\n' "$art_html" | rehydrate
else
  echo '<p class="empty">no rows</p>'
fi
echo '</section>'
echo '</div>' # /panel-artifacts

echo '</div>' # /.tabs

# Inline script: Artifacts filter + pagination. Static-HTML dashboard, no
# server, no external deps — a tiny handler is the right shape here.
cat <<'SCRIPT'
<script>
(function () {
  var table = document.getElementById('art-table');
  if (!table) return;
  var rows = Array.prototype.slice.call(table.tBodies[0].rows).slice(1); // skip header row
  // sqlite3 -html emits <TR> for the header without a <THEAD>, so the first
  // row of tBodies[0] is the header. Keep it visible; slice above drops it
  // from the paged set.
  var filterEl = document.getElementById('art-filter');
  var pageEl   = document.getElementById('art-page');
  var prevBtn  = document.getElementById('art-prev');
  var nextBtn  = document.getElementById('art-next');
  var pageSize = 50;
  var page = 0;
  var matched = rows;
  function apply() {
    var q = filterEl.value.trim().toLowerCase();
    matched = q ? rows.filter(function (r) { return r.textContent.toLowerCase().indexOf(q) !== -1; }) : rows;
    var totalPages = Math.max(1, Math.ceil(matched.length / pageSize));
    if (page >= totalPages) page = totalPages - 1;
    if (page < 0) page = 0;
    rows.forEach(function (r) { r.style.display = 'none'; });
    matched.slice(page * pageSize, (page + 1) * pageSize).forEach(function (r) { r.style.display = ''; });
    pageEl.textContent = (page + 1) + '/' + totalPages + ' (' + matched.length + ' rows)';
    prevBtn.disabled = page === 0;
    nextBtn.disabled = page >= totalPages - 1;
  }
  prevBtn.addEventListener('click', function () { page--; apply(); });
  nextBtn.addEventListener('click', function () { page++; apply(); });
  filterEl.addEventListener('input', function () { page = 0; apply(); });
  apply();
})();
</script>
SCRIPT

cat <<'TAIL'
<footer style="margin-top:32px;color:var(--muted);font-size:12px">
  generated by <code>dashboard/generate.sh</code> — regenerate any time; no cache, no server.
</footer>
</body></html>
TAIL

} > "$OUT"

echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
