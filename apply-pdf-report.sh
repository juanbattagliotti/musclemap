#!/usr/bin/env bash
# =============================================================================
# MuscleMap — apply feat/session-report branch
#
# Adds a "Generate report" button that produces a one-page PDF summary of
# the session: reps, ROM, form scorecard, asymmetry, rep-by-rep timeline.
#
# Usage:
#   cd musclemap
#   save this file as apply-pdf-report.sh in that folder
#   chmod +x apply-pdf-report.sh
#   ./apply-pdf-report.sh
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — apply PDF report         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# --- Preflight ---
if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ This doesn't look like your musclemap folder.${NC}"
  echo "  Make sure you're inside the project folder before running this script."
  exit 1
fi

if [ ! -d ".git" ]; then
  echo -e "${RED}✗ No git repo found here.${NC}"
  exit 1
fi

if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ You have uncommitted changes.${NC}"
  echo "  Commit or stash them first:"
  echo "    git add . && git commit -m 'wip'"
  exit 1
fi

# Make sure we're on main before branching
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo -e "${YELLOW}⚠ You're on '$CURRENT_BRANCH', switching to main first…${NC}"
  git checkout main
fi

echo -e "${GREEN}✓${NC} Inside musclemap repo, on main, tree is clean"
echo ""

# --- Install jsPDF ---
echo -e "${BLUE}→ Installing jsPDF (PDF generation library)…${NC}"
npm install jspdf --save > /dev/null 2>&1
echo -e "${GREEN}✓${NC} jspdf installed"
echo ""

# --- Create feature branch ---
echo -e "${BLUE}→ Creating feature branch…${NC}"
if git show-ref --verify --quiet refs/heads/feat/session-report; then
  echo -e "${YELLOW}⚠${NC} Branch 'feat/session-report' exists. Deleting and recreating."
  git branch -D feat/session-report
fi
git checkout -b feat/session-report

# =============================================================================
# WRITE FILES
# =============================================================================

# --- Create src/analytics/session-summary.js ---
echo -e "${BLUE}→ Writing src/analytics/session-summary.js…${NC}"
mkdir -p src/analytics
cat > src/analytics/session-summary.js <<'EOF'
// =========================================================================
// Build a session summary from the per-arm state.
// This is the single source of truth for what appears in reports.
// =========================================================================

export function buildSessionSummary(armL, armR, exercise, sessionMeta = {}) {
  const totalReps = armL.repCount + armR.repCount;
  if (totalReps === 0) {
    return null;
  }

  const summary = {
    // Metadata
    meta: {
      exercise: exercise.name,
      exerciseId: exercise.id,
      date: new Date(),
      clientName: sessionMeta.clientName || '',
      trainerName: sessionMeta.trainerName || '',
      notes: sessionMeta.notes || '',
    },

    // Totals
    totals: {
      totalReps,
      repsL: armL.repCount,
      repsR: armR.repCount,
      goodFormReps: countGood(armL) + countGood(armR),
      warningFormReps: countWarning(armL) + countWarning(armR),
      badFormReps: countBad(armL) + countBad(armR),
      formScore: formScore(armL, armR),  // 0-100
    },

    // Per-side details
    left: sideDetails(armL),
    right: sideDetails(armR),

    // Asymmetry (based on peak activation across matched reps)
    asymmetry: asymmetryFromReps(armL, armR),

    // Rep-by-rep timeline
    timeline: timeline(armL, armR),
  };

  return summary;
}

function countGood(arm)    { return arm.repFormFlags.filter(f => f === 'good').length; }
function countWarning(arm) { return arm.repFormFlags.filter(f => f === 'warning').length; }
function countBad(arm)     { return arm.repFormFlags.filter(f => f === 'bad').length; }

function formScore(armL, armR) {
  const total = armL.repCount + armR.repCount;
  if (total === 0) return 0;
  // Weight: good=1.0, warning=0.5, bad=0.0
  const weighted = countGood(armL) + countGood(armR)
                 + 0.5 * (countWarning(armL) + countWarning(armR));
  return Math.round((weighted / total) * 100);
}

function sideDetails(arm) {
  if (arm.repCount === 0) {
    return { reps: 0, avgPeak: 0, avgROM: [0, 0], goodRepPct: 0 };
  }
  const avgPeak = arm.repPeaks.reduce((a, b) => a + b, 0) / arm.repPeaks.length;
  const avgMin = arm.repROMs.reduce((a, [m]) => a + m, 0) / arm.repROMs.length;
  const avgMax = arm.repROMs.reduce((a, [, M]) => a + M, 0) / arm.repROMs.length;
  const goodRepPct = Math.round((countGood(arm) / arm.repCount) * 100);
  return {
    reps: arm.repCount,
    avgPeak: Math.round(avgPeak * 100),
    avgROM: [Math.round(avgMin), Math.round(avgMax)],
    goodRepPct,
    repPeaks: [...arm.repPeaks],
    repROMs: [...arm.repROMs],
    repFormFlags: [...arm.repFormFlags],
  };
}

function asymmetryFromReps(armL, armR) {
  const minReps = Math.min(armL.repPeaks.length, armR.repPeaks.length);
  if (minReps < 1) return { index: 0, verdict: 'Insufficient data', stronger: null };

  const window = Math.min(minReps, 5);
  const mean = (arr) => arr.slice(-window).reduce((a, b) => a + b, 0) / window;
  const meanL = mean(armL.repPeaks);
  const meanR = mean(armR.repPeaks);
  const avg = (meanL + meanR) / 2;
  if (avg === 0) return { index: 0, verdict: 'Insufficient data', stronger: null };

  const signed = (meanR - meanL) / avg;
  const abs = Math.abs(signed);

  let verdict;
  if (abs < 0.05) verdict = 'Well balanced';
  else if (abs < 0.12) verdict = 'Slight asymmetry';
  else verdict = 'Notable asymmetry';

  return {
    index: Math.round(abs * 100 * 10) / 10,  // 1 decimal
    signed,
    verdict,
    stronger: abs < 0.05 ? null : (signed > 0 ? 'right' : 'left'),
  };
}

function timeline(armL, armR) {
  // Interleave L and R reps in order for a clean timeline view
  const maxReps = Math.max(armL.repPeaks.length, armR.repPeaks.length);
  const out = [];
  for (let i = 0; i < maxReps; i++) {
    if (i < armL.repPeaks.length) {
      out.push({ side: 'L', rep: i + 1, peak: armL.repPeaks[i], rom: armL.repROMs[i], form: armL.repFormFlags[i] });
    }
    if (i < armR.repPeaks.length) {
      out.push({ side: 'R', rep: i + 1, peak: armR.repPeaks[i], rom: armR.repROMs[i], form: armR.repFormFlags[i] });
    }
  }
  return out;
}
EOF

# --- Create src/reports/pdf-report.js ---
echo -e "${BLUE}→ Writing src/reports/pdf-report.js…${NC}"
mkdir -p src/reports
cat > src/reports/pdf-report.js <<'EOF'
import { jsPDF } from 'jspdf';

// =========================================================================
// Generate a one-page PDF session report.
// Takes a session summary (from buildSessionSummary) and returns a jsPDF
// instance ready to save.
// =========================================================================

const COLORS = {
  text: '#0c1220',
  textDim: '#5a6070',
  accent: '#00c878',
  warn: '#e67700',
  bad: '#d63838',
  rule: '#dde2ec',
  panel: '#f6f8fb',
};

export function generateSessionReport(summary, opts = {}) {
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  const M = 40;  // margin

  let y = M;

  // ---- Header bar ----
  doc.setFillColor(12, 18, 32);
  doc.rect(0, 0, W, 70, 'F');
  doc.setTextColor('#ffffff');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(20);
  doc.text('MUSCLEMAP', M, 35);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor('#8090a0');
  doc.text('Movement analysis · Session report', M, 52);

  // Date top-right
  doc.setTextColor('#c0c8d4');
  doc.setFontSize(10);
  const dateStr = summary.meta.date.toLocaleDateString('en-GB', {
    year: 'numeric', month: 'long', day: 'numeric'
  });
  doc.text(dateStr, W - M, 35, { align: 'right' });
  doc.setFontSize(9);
  doc.setTextColor('#8090a0');
  doc.text(summary.meta.date.toLocaleTimeString('en-GB', {
    hour: '2-digit', minute: '2-digit'
  }), W - M, 52, { align: 'right' });

  y = 90;

  // ---- Session metadata ----
  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(16);
  doc.text(summary.meta.exercise, M, y);
  y += 20;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);
  doc.setTextColor(COLORS.textDim);
  const metaLine = [];
  if (summary.meta.clientName) metaLine.push('Client: ' + summary.meta.clientName);
  if (summary.meta.trainerName) metaLine.push('Trainer: ' + summary.meta.trainerName);
  if (metaLine.length) {
    doc.text(metaLine.join('   ·   '), M, y);
    y += 15;
  }

  y += 8;
  drawRule(doc, M, y, W - M);
  y += 18;

  // ---- Top metrics row (3 panels) ----
  const panelWidth = (W - M * 2 - 20) / 3;
  drawMetricPanel(doc, M, y, panelWidth, 70,
    'TOTAL REPS', String(summary.totals.totalReps),
    summary.totals.repsL + ' left · ' + summary.totals.repsR + ' right');

  drawMetricPanel(doc, M + panelWidth + 10, y, panelWidth, 70,
    'FORM SCORE', summary.totals.formScore + '%',
    scoreDescriptor(summary.totals.formScore),
    scoreColor(summary.totals.formScore));

  drawMetricPanel(doc, M + (panelWidth + 10) * 2, y, panelWidth, 70,
    'ASYMMETRY', summary.asymmetry.index + '%',
    summary.asymmetry.verdict,
    asymmetryColor(summary.asymmetry.index));

  y += 90;

  // ---- Form breakdown ----
  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('FORM BREAKDOWN', M, y);
  y += 14;

  const total = summary.totals.totalReps;
  const good = summary.totals.goodFormReps;
  const warn = summary.totals.warningFormReps;
  const bad  = summary.totals.badFormReps;

  drawStackedBar(doc, M, y, W - M * 2, 16, [
    { value: good, color: COLORS.accent, label: 'Clean' },
    { value: warn, color: COLORS.warn, label: 'Warning' },
    { value: bad,  color: COLORS.bad,   label: 'Bad' },
  ], total);
  y += 22;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(COLORS.textDim);
  doc.text(
    good + ' clean    ' + warn + ' with warnings    ' + bad + ' with issues',
    M, y
  );
  y += 20;

  // ---- Per-side breakdown ----
  drawRule(doc, M, y, W - M);
  y += 18;

  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('PER-SIDE SUMMARY', M, y);
  y += 14;

  const colW = (W - M * 2 - 15) / 2;
  const sideY = y;
  drawSidePanel(doc, M,             sideY, colW, 'LEFT',  summary.left,  COLORS.accent);
  drawSidePanel(doc, M + colW + 15, sideY, colW, 'RIGHT', summary.right, '#e6a900');
  y = sideY + 75;

  // ---- Rep timeline ----
  drawRule(doc, M, y, W - M);
  y += 18;

  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('REP-BY-REP TIMELINE', M, y);
  y += 14;

  drawRepTimeline(doc, M, y, W - M * 2, 60, summary.timeline);
  y += 70;

  // Legend
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text('Bar height = peak activation for that rep · Color = form verdict', M, y);
  y += 14;

  // Key
  drawLegendDot(doc, M, y, COLORS.accent); doc.text('Clean', M + 10, y + 3);
  drawLegendDot(doc, M + 55, y, COLORS.warn); doc.text('Warning', M + 65, y + 3);
  drawLegendDot(doc, M + 120, y, COLORS.bad); doc.text('Bad', M + 130, y + 3);
  y += 18;

  // ---- Notes ----
  if (summary.meta.notes) {
    drawRule(doc, M, y, W - M);
    y += 18;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(COLORS.text);
    doc.text('NOTES', M, y);
    y += 14;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(COLORS.textDim);
    const notes = doc.splitTextToSize(summary.meta.notes, W - M * 2);
    doc.text(notes, M, y);
    y += notes.length * 12 + 10;
  }

  // ---- Footer ----
  doc.setFontSize(8);
  doc.setTextColor('#a0a8b8');
  doc.text('Generated by MuscleMap · Rule-based activation estimate, not clinical EMG',
    W / 2, H - 20, { align: 'center' });

  return doc;
}

// -------------------------------------------------------------------------
// Drawing helpers
// -------------------------------------------------------------------------

function drawRule(doc, x, y, x2) {
  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.line(x, y, x2, y);
}

function drawMetricPanel(doc, x, y, w, h, label, value, sublabel, valueColor) {
  doc.setFillColor(COLORS.panel);
  doc.roundedRect(x, y, w, h, 6, 6, 'F');

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text(label, x + 12, y + 16);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(24);
  doc.setTextColor(valueColor || COLORS.text);
  doc.text(value, x + 12, y + 44);

  if (sublabel) {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(COLORS.textDim);
    doc.text(sublabel, x + 12, y + 60);
  }
}

function drawStackedBar(doc, x, y, w, h, segments, total) {
  let cursor = x;
  segments.forEach(seg => {
    const segW = total > 0 ? (seg.value / total) * w : 0;
    if (segW > 0) {
      doc.setFillColor(seg.color);
      doc.rect(cursor, y, segW, h, 'F');
      cursor += segW;
    }
  });
  // outline
  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.rect(x, y, w, h);
}

function drawSidePanel(doc, x, y, w, label, side, accentColor) {
  doc.setFillColor(COLORS.panel);
  doc.roundedRect(x, y, w, 70, 6, 6, 'F');

  // Label
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.setTextColor(accentColor);
  doc.text(label, x + 12, y + 15);

  // Rep count
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.setTextColor(COLORS.text);
  doc.text(side.reps + ' reps', x + 12, y + 35);

  // Details
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(COLORS.textDim);
  doc.text('Avg peak: ' + side.avgPeak + '%', x + 12, y + 50);
  doc.text('Avg ROM: ' + side.avgROM[0] + '–' + side.avgROM[1] + '°', x + 12, y + 62);

  // Good-rep badge (right side of panel)
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(18);
  doc.setTextColor(scoreColor(side.goodRepPct));
  doc.text(side.goodRepPct + '%', x + w - 12, y + 36, { align: 'right' });
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text('clean', x + w - 12, y + 50, { align: 'right' });
}

function drawRepTimeline(doc, x, y, w, h, timeline) {
  if (timeline.length === 0) return;

  const gap = 3;
  const barW = Math.max(2, Math.min(20, (w - gap * (timeline.length - 1)) / timeline.length));
  const maxPeak = Math.max(...timeline.map(r => r.peak), 0.1);

  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.line(x, y + h, x + w, y + h);  // baseline

  timeline.forEach((rep, i) => {
    const barX = x + i * (barW + gap);
    const barH = (rep.peak / maxPeak) * h;
    const barY = y + h - barH;
    const color =
      rep.form === 'bad' ? COLORS.bad :
      rep.form === 'warning' ? COLORS.warn :
      (rep.side === 'L' ? COLORS.accent : '#e6a900');
    doc.setFillColor(color);
    doc.rect(barX, barY, barW, barH, 'F');
  });
}

function drawLegendDot(doc, x, y, color) {
  doc.setFillColor(color);
  doc.circle(x + 4, y, 3, 'F');
}

function scoreColor(pct) {
  if (pct >= 80) return COLORS.accent;
  if (pct >= 60) return COLORS.warn;
  return COLORS.bad;
}
function scoreDescriptor(pct) {
  if (pct >= 90) return 'Excellent';
  if (pct >= 75) return 'Good';
  if (pct >= 60) return 'Needs work';
  return 'Needs attention';
}
function asymmetryColor(pct) {
  if (pct < 5) return COLORS.accent;
  if (pct < 12) return COLORS.warn;
  return COLORS.bad;
}
EOF

# --- Update src/main.js to wire up the report button ---
echo -e "${BLUE}→ Updating src/main.js (adding report handler)…${NC}"
# We'll insert the imports and handler using python for precision
python3 <<'PYEOF'
import re

with open('src/main.js', 'r') as f:
    src = f.read()

# 1. Add imports if not present
if 'buildSessionSummary' not in src:
    # Find the line that imports from './sources/demo.js'
    src = src.replace(
        "import { runDemo, stopDemo } from './sources/demo.js';",
        "import { runDemo, stopDemo } from './sources/demo.js';\n"
        "import { buildSessionSummary } from './analytics/session-summary.js';\n"
        "import { generateSessionReport } from './reports/pdf-report.js';"
    )

# 2. Add the report button listener inside init()
if 'onGenerateReport' not in src:
    src = src.replace(
        "dom.stopBtn.addEventListener('click', onStop);",
        "dom.stopBtn.addEventListener('click', onStop);\n"
        "  if (dom.reportBtn) dom.reportBtn.addEventListener('click', onGenerateReport);"
    )

# 3. Add the handler function just before `init();` at the end
if 'function onGenerateReport' not in src:
    handler = '''
function onGenerateReport() {
  const summary = buildSessionSummary(armL, armR, currentExercise, {
    clientName: dom.clientNameInput?.value || '',
    trainerName: dom.trainerNameInput?.value || '',
    notes: dom.notesInput?.value || '',
  });
  if (!summary) {
    log('no reps recorded yet — nothing to report', 'err');
    return;
  }
  const doc = generateSessionReport(summary);
  const filename = buildFilename(summary);
  doc.save(filename);
  log('report saved: ' + filename, 'ok');
}

function buildFilename(summary) {
  const d = summary.meta.date;
  const pad = (n) => String(n).padStart(2, '0');
  const datePart = d.getFullYear() + pad(d.getMonth()+1) + pad(d.getDate());
  const timePart = pad(d.getHours()) + pad(d.getMinutes());
  const exercise = summary.meta.exerciseId;
  const client = (summary.meta.clientName || 'session').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
  return `musclemap_${exercise}_${client}_${datePart}-${timePart}.pdf`;
}

'''
    src = src.replace('init();', handler + 'init();')

with open('src/main.js', 'w') as f:
    f.write(src)
print('src/main.js updated')
PYEOF

# --- Update src/ui/dom.js to add new element refs ---
echo -e "${BLUE}→ Updating src/ui/dom.js…${NC}"
python3 <<'PYEOF'
with open('src/ui/dom.js', 'r') as f:
    src = f.read()

if 'reportBtn' not in src:
    src = src.replace(
        "exerciseSelect: $('exerciseSelect'),",
        "exerciseSelect: $('exerciseSelect'),\n\n"
        "  reportBtn: $('reportBtn'),\n"
        "  clientNameInput: $('clientName'),\n"
        "  trainerNameInput: $('trainerName'),\n"
        "  notesInput: $('sessionNotes'),"
    )

with open('src/ui/dom.js', 'w') as f:
    f.write(src)
print('src/ui/dom.js updated')
PYEOF

# --- Update index.html: add report button + client/trainer/notes fields ---
echo -e "${BLUE}→ Updating index.html…${NC}"
python3 <<'PYEOF'
with open('index.html', 'r') as f:
    html = f.read()

# Update version tag
import re
html = re.sub(
    r'<span class="tag">MUSCLEMAP · v0\.[0-9]+[^<]*</span>',
    '<span class="tag">MUSCLEMAP · v0.5 · SESSION REPORTS</span>',
    html
)

# Add Generate report button next to Stop button in controls row (idempotent)
if 'id="reportBtn"' not in html:
    html = html.replace(
        '<button id="stopBtn" class="danger" style="display:none;">Stop</button>',
        '<button id="stopBtn" class="danger" style="display:none;">Stop</button>\n'
        '          <button id="reportBtn" class="accent-outline">Generate report</button>'
    )

# Add client/trainer/notes inputs as a collapsible section above controls
if 'id="clientName"' not in html:
    session_meta_block = '''
        <div class="session-meta">
          <div class="session-meta-row">
            <label>Client <input type="text" id="clientName" placeholder="e.g. Marco R."></label>
            <label>Trainer <input type="text" id="trainerName" placeholder="e.g. Juan B."></label>
          </div>
          <label class="full-width">Notes
            <textarea id="sessionNotes" rows="2" placeholder="Anything to remember about this session…"></textarea>
          </label>
        </div>
'''
    html = html.replace(
        '<div class="log" id="log"></div>',
        session_meta_block + '        <div class="log" id="log"></div>'
    )

with open('index.html', 'w') as f:
    f.write(html)
print('index.html updated')
PYEOF

# --- Append CSS for the new UI elements ---
echo -e "${BLUE}→ Appending styles for report UI…${NC}"
if ! grep -q "session-meta" src/ui/styles.css; then
  cat >> src/ui/styles.css <<'EOF'

/* --- Report button (outline style) --- */
button.accent-outline {
  background: transparent;
  color: var(--accent);
  border: 1px solid var(--accent);
}
button.accent-outline:hover:not(:disabled) {
  background: rgba(0,255,157,0.08);
  transform: translateY(-1px);
}

/* --- Session metadata inputs --- */
.session-meta {
  margin-top: 14px;
  padding: 14px;
  background: rgba(255,255,255,0.02);
  border: 1px solid var(--border);
  border-radius: 10px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.session-meta-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.session-meta label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-family: 'Menlo', monospace;
  font-size: 10px;
  letter-spacing: 0.15em;
  color: var(--text-dim);
  text-transform: uppercase;
}
.session-meta label.full-width { grid-column: 1 / -1; }
.session-meta input,
.session-meta textarea {
  background: var(--bg);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 8px 10px;
  font-size: 13px;
  font-family: inherit;
  font-weight: normal;
  letter-spacing: normal;
  text-transform: none;
  resize: vertical;
}
.session-meta input:focus,
.session-meta textarea:focus {
  outline: none;
  border-color: var(--accent);
}
EOF
  echo -e "${GREEN}  ✓${NC} styles appended"
else
  echo -e "${YELLOW}  ⚠ session-meta styles already present, skipping${NC}"
fi

# --- Commit ---
echo ""
echo -e "${BLUE}→ Committing changes…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit — files may already be up to date${NC}"
else
  git commit -q -m "feat: add one-page PDF session report

- New module src/analytics/session-summary.js: pure function that
  transforms per-arm state into a structured summary (totals, per-side
  details, asymmetry, rep timeline)
- New module src/reports/pdf-report.js: renders the summary as a
  designed one-page A4 PDF using jsPDF (header, metric panels, form
  breakdown, per-side summary, rep timeline, notes)
- Wire 'Generate report' button in the UI
- Client name / trainer name / notes inputs for report metadata
- Filename template: musclemap_{exercise}_{client}_{YYYYMMDD-HHMM}.pdf
- jsPDF added as a dependency"
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        PDF report feature ready        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it locally:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  1. Open http://localhost:5173"
echo -e "  2. Fill in Client name + optional Trainer name and Notes"
echo -e "  3. Click ${BLUE}Demo${NC} or ${BLUE}Start webcam${NC}, do a few reps"
echo -e "  4. Click ${BLUE}Stop${NC}"
echo -e "  5. Click ${BLUE}Generate report${NC} — PDF downloads immediately"
echo ""
echo -e "${YELLOW}Merge to main when happy:${NC}"
echo ""
echo -e "  ${BLUE}git push -u origin feat/session-report${NC}"
echo -e "  ${BLUE}git checkout main${NC}"
echo -e "  ${BLUE}git merge feat/session-report${NC}"
echo -e "  ${BLUE}git push${NC}"
echo -e "  ${BLUE}git branch -d feat/session-report${NC}"
echo ""
echo -e "${YELLOW}If something's broken:${NC}"
echo -e "  ${BLUE}git checkout main${NC}"
echo -e "  ${BLUE}git branch -D feat/session-report${NC}"
echo ""
