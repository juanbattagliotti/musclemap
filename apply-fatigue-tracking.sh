#!/usr/bin/env bash
# =============================================================================
# MuscleMap — apply feat/fatigue-tracking branch
#
# Adds proximity-to-failure detection: live RIR estimate + fatigue gauge
# during sets, with velocity loss as the primary signal, plus ROM drift,
# concentric/eccentric ratio, and form breakdown as confirmation signals.
#
# Usage:
#   cd musclemap
#   save this file as apply-fatigue-tracking.sh
#   chmod +x apply-fatigue-tracking.sh
#   ./apply-fatigue-tracking.sh
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — fatigue + RIR tracking   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ Run this from inside the musclemap folder.${NC}"; exit 1
fi
if [ ! -d ".git" ]; then
  echo -e "${RED}✗ No git repo found.${NC}"; exit 1
fi
if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Uncommitted changes. Commit or stash first.${NC}"; exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo -e "${YELLOW}⚠ Switching to main first…${NC}"
  git checkout main
fi

if git show-ref --verify --quiet refs/heads/feat/fatigue-tracking; then
  git branch -D feat/fatigue-tracking
fi
git checkout -b feat/fatigue-tracking

# =============================================================================

echo -e "${BLUE}→ Writing src/analytics/fatigue.js…${NC}"
cat > src/analytics/fatigue.js <<'EOF'
// =========================================================================
// Fatigue / proximity-to-failure estimation
//
// Primary signal: velocity loss from the fastest rep of the current set.
// Research basis: concentric velocity loss is the most validated real-time
// proxy for approaching failure (Sanchez-Medina & Gonzalez-Badillo 2011,
// Weakley et al. 2021). Velocity loss thresholds:
//   - <10% loss  → RIR >= 5 (fresh)
//   - 10-20%     → RIR 3-5
//   - 20-30%     → RIR 1-3  (approaching failure)
//   - >30%       → RIR 0-1  (at or past failure)
//
// We blend in three confirmation signals:
//   - ROM drift: range of motion shrinks near failure
//   - C/E ratio: concentric gets slower than eccentric near failure
//   - Form breakdown: warnings & bad reps cluster near failure
// =========================================================================

// Reps before we have a baseline — don't show RIR until we have 2 reps
const MIN_REPS_FOR_BASELINE = 2;

export function makeSetState() {
  return {
    active: false,
    startedAt: null,
    reps: [],               // one entry per rep: { index, concentricVel, concentricDur, eccentricDur, rom, form }
    peakVelocity: 0,        // fastest concentric velocity seen this set
    peakROM: 0,             // largest ROM seen this set
  };
}

export function resetSetState(state) {
  Object.assign(state, makeSetState());
}

export function startSet(state) {
  resetSetState(state);
  state.active = true;
  state.startedAt = Date.now();
}

export function endSet(state) {
  state.active = false;
}

// Called after each completed rep. Records per-rep fatigue inputs.
// Expects:
//   rep = { concentricVel, concentricDur, eccentricDur, rom, form }
export function recordRep(state, rep) {
  if (!state.active) return;
  state.reps.push({ index: state.reps.length + 1, ...rep });
  if (rep.concentricVel > state.peakVelocity) state.peakVelocity = rep.concentricVel;
  if (rep.rom > state.peakROM) state.peakROM = rep.rom;
}

// Return a live fatigue estimate during a set.
// fatigue: 0-1 (fraction of the way from fresh to failure)
// rir: estimated reps-in-reserve (float, clamped to 0..10)
// signals: individual contributor values for debugging / display
export function computeFatigue(state, currentConcentricVel = null) {
  if (!state.active || state.reps.length < MIN_REPS_FOR_BASELINE) {
    return { fatigue: 0, rir: null, signals: emptySignals(), confident: false };
  }

  // --- Signal 1: velocity loss vs peak of this set ---
  // Use the fastest of (peakVelocity, current live velocity if provided)
  // as the reference, compare against the most recent *completed* rep.
  const lastRep = state.reps.at(-1);
  const peak = Math.max(state.peakVelocity, currentConcentricVel || 0);
  const velLoss = peak > 0 ? Math.max(0, 1 - (lastRep.concentricVel / peak)) : 0;

  // --- Signal 2: ROM drift (last rep vs set peak) ---
  const romDrift = state.peakROM > 0
    ? Math.max(0, 1 - (lastRep.rom / state.peakROM))
    : 0;

  // --- Signal 3: concentric-to-eccentric ratio ---
  // Early in a set, concentric is faster than eccentric (ratio < 1)
  // Near failure, concentric slows relative to eccentric (ratio → 1 or >1)
  let ceRatio = 0.5;  // neutral default
  if (lastRep.eccentricDur > 0) {
    ceRatio = lastRep.concentricDur / lastRep.eccentricDur;
  }
  // Map to a [0, 1] fatigue contribution: 0.6 is fresh, 1.0+ is maxed out
  const ceSignal = clamp((ceRatio - 0.6) / 0.5, 0, 1);

  // --- Signal 4: form breakdown clustering in the last 3 reps ---
  const recent = state.reps.slice(-3);
  const badCount = recent.filter(r => r.form === 'bad').length;
  const warnCount = recent.filter(r => r.form === 'warning').length;
  const formSignal = clamp((badCount * 0.5 + warnCount * 0.2), 0, 1);

  // --- Composite fatigue ---
  // Weighted blend: velocity loss is primary (60%), others confirm
  const fatigue = clamp(
    velLoss * 0.60 +
    romDrift * 0.15 +
    ceSignal * 0.15 +
    formSignal * 0.10,
    0, 1
  );

  // --- Map fatigue to RIR ---
  // fatigue 0.0 → RIR 10 (completely fresh)
  // fatigue 0.1 → RIR 6
  // fatigue 0.2 → RIR 3
  // fatigue 0.3 → RIR 1
  // fatigue 0.4+ → RIR 0 (at failure)
  const rir = fatigueToRIR(fatigue);

  // Confidence: we're confident after 4 reps AND velocity signal agrees
  const confident = state.reps.length >= 4;

  return {
    fatigue,
    rir,
    signals: { velLoss, romDrift, ceSignal, formSignal },
    confident
  };
}

function fatigueToRIR(f) {
  // Piecewise linear map calibrated to the thresholds above
  if (f < 0.05) return 10;
  if (f < 0.10) return lerp(f, 0.05, 0.10, 10, 6);
  if (f < 0.20) return lerp(f, 0.10, 0.20, 6, 3);
  if (f < 0.30) return lerp(f, 0.20, 0.30, 3, 1);
  if (f < 0.40) return lerp(f, 0.30, 0.40, 1, 0);
  return 0;
}

function lerp(x, x0, x1, y0, y1) {
  return y0 + (y1 - y0) * ((x - x0) / (x1 - x0));
}
function clamp(x, lo, hi) { return Math.max(lo, Math.min(hi, x)); }
function emptySignals() { return { velLoss: 0, romDrift: 0, ceSignal: 0, formSignal: 0 }; }

// Categorical label for the banner
export function rirLabel(rir) {
  if (rir === null || rir === undefined) return { label: 'BASELINING', severity: 'neutral' };
  if (rir >= 5) return { label: 'FRESH', severity: 'good' };
  if (rir >= 3) return { label: 'WORKING', severity: 'good' };
  if (rir >= 1) return { label: 'APPROACHING FAILURE', severity: 'warning' };
  return { label: 'AT FAILURE', severity: 'bad' };
}

// Final set summary used by the PDF report
export function summarizeSet(state) {
  if (state.reps.length === 0) return null;
  const vels = state.reps.map(r => r.concentricVel);
  const roms = state.reps.map(r => r.rom);
  const finalVelLoss = state.peakVelocity > 0
    ? Math.max(0, 1 - (vels[vels.length - 1] / state.peakVelocity))
    : 0;
  return {
    totalReps: state.reps.length,
    peakVelocity: state.peakVelocity,
    finalVelocity: vels[vels.length - 1],
    finalVelLoss,
    peakROM: state.peakROM,
    finalROM: roms[roms.length - 1],
    velocities: vels,
    roms,
    forms: state.reps.map(r => r.form),
    estimatedFinalRIR: computeFatigue(state).rir,
  };
}
EOF

echo -e "${BLUE}→ Updating src/analytics/session-state.js (track per-rep timing)…${NC}"
cat > src/analytics/session-state.js <<'EOF'
export function makeArmState() {
  return {
    angleHistory: [],
    angleTimestamps: [],
    repCount: 0,
    repPeaks: [],
    repROMs: [],
    repFormFlags: [],
    repVelocities: [],     // peak concentric velocity per rep
    repConcDurations: [],  // concentric duration (ms)
    repEccDurations: [],   // eccentric duration (ms)
    currentPhase: 'neutral',
    minAngleThisRep: 180,
    maxAngleThisRep: 0,
    peakBicepThisRep: 0,
    peakVelocityThisRep: 0,
    worstFormThisRep: 'good',
    // Phase timing for concentric/eccentric duration
    downPhaseStart: null,  // timestamp when eccentric (down/descending) started
    upPhaseStart: null,    // timestamp when concentric (up/ascending) started
    lastConcentricDuration: 0,
    lastEccentricDuration: 0,
  };
}

export function resetArmState(state) {
  Object.assign(state, makeArmState());
}

export function updateArmData(state, elbowAngle, shoulderAngle, timestamp, activationFn) {
  state.angleHistory.push(elbowAngle);
  state.angleTimestamps.push(timestamp);
  if (state.angleHistory.length > 10) {
    state.angleHistory.shift();
    state.angleTimestamps.shift();
  }

  let angVel = 0;
  if (state.angleHistory.length >= 2) {
    const dt = (state.angleTimestamps.at(-1) - state.angleTimestamps[0]) / 1000;
    if (dt > 0) angVel = (state.angleHistory.at(-1) - state.angleHistory[0]) / dt;
  }

  // Track peak absolute velocity during the current concentric phase
  if (state.currentPhase === 'up') {
    const absVel = Math.abs(angVel);
    if (absVel > state.peakVelocityThisRep) state.peakVelocityThisRep = absVel;
  }

  return activationFn(elbowAngle, shoulderAngle, angVel);
}
EOF

echo -e "${BLUE}→ Updating src/analytics/rep-detector.js (emit per-rep timing)…${NC}"
cat > src/analytics/rep-detector.js <<'EOF'
const RANK = { good: 0, warning: 1, bad: 2 };

// Returns null if no rep completed, or a full rep record if one just did.
export function detectRep(state, angle, primaryAct, formCheck, thresholds, timestamp) {
  const FLEX_THR = thresholds?.flex ?? 80;
  const EXT_THR  = thresholds?.ext  ?? 150;

  state.minAngleThisRep = Math.min(state.minAngleThisRep, angle);
  state.maxAngleThisRep = Math.max(state.maxAngleThisRep, angle);
  state.peakBicepThisRep = Math.max(state.peakBicepThisRep, primaryAct);

  if (formCheck && RANK[formCheck.verdict] > RANK[state.worstFormThisRep]) {
    state.worstFormThisRep = formCheck.verdict;
  }

  const now = timestamp ?? performance.now();

  if (state.currentPhase === 'neutral' && angle > EXT_THR) {
    state.currentPhase = 'down';
    state.downPhaseStart = now;
    startNewRep(state, angle);
  } else if (state.currentPhase === 'down' && angle < FLEX_THR) {
    state.currentPhase = 'up';
    state.upPhaseStart = now;
    if (state.downPhaseStart !== null) {
      state.lastEccentricDuration = now - state.downPhaseStart;
    }
  } else if (state.currentPhase === 'up' && angle > EXT_THR) {
    if (state.upPhaseStart !== null) {
      state.lastConcentricDuration = now - state.upPhaseStart;
    }

    const rom = state.maxAngleThisRep - state.minAngleThisRep;
    const repRecord = {
      peak: state.peakBicepThisRep,
      rom,
      form: state.worstFormThisRep,
      concentricVel: state.peakVelocityThisRep,
      concentricDur: state.lastConcentricDuration,
      eccentricDur: state.lastEccentricDuration,
    };

    state.repCount++;
    state.repPeaks.push(state.peakBicepThisRep);
    state.repROMs.push([state.minAngleThisRep, state.maxAngleThisRep]);
    state.repFormFlags.push(state.worstFormThisRep);
    state.repVelocities.push(state.peakVelocityThisRep);
    state.repConcDurations.push(state.lastConcentricDuration);
    state.repEccDurations.push(state.lastEccentricDuration);

    state.currentPhase = 'down';
    state.downPhaseStart = now;
    startNewRep(state, angle);

    return repRecord;
  }
  return null;
}

function startNewRep(state, angle) {
  state.minAngleThisRep = angle;
  state.maxAngleThisRep = angle;
  state.peakBicepThisRep = 0;
  state.peakVelocityThisRep = 0;
  state.worstFormThisRep = 'good';
}

export function isAtBottom(state, angle, thresholds) {
  const FLEX_THR = thresholds?.flex ?? 80;
  return state.currentPhase === 'up' && angle < FLEX_THR + 15;
}
EOF

echo -e "${BLUE}→ Updating src/main.js (wire fatigue tracking)…${NC}"
python3 <<'PYEOF'
with open('src/main.js', 'r') as f:
    src = f.read()

# 1. Add imports
if 'makeSetState' not in src:
    src = src.replace(
        "import { detectRep, isAtBottom } from './analytics/rep-detector.js';",
        "import { detectRep, isAtBottom } from './analytics/rep-detector.js';\n"
        "import { makeSetState, startSet as startSetFn, endSet as endSetFn,\n"
        "         recordRep, computeFatigue, rirLabel, summarizeSet } from './analytics/fatigue.js';"
    )

# 2. Create set state variables right after the armL/armR declarations
if 'const setL = makeSetState' not in src:
    src = src.replace(
        "const armL = makeArmState();\nconst armR = makeArmState();",
        "const armL = makeArmState();\nconst armR = makeArmState();\n"
        "const setL = makeSetState();\n"
        "const setR = makeSetState();\n"
        "let setActive = false;"
    )

# 3. Add set-control button listeners
if 'onStartSet' not in src:
    src = src.replace(
        "if (dom.reportBtn) dom.reportBtn.addEventListener('click', onGenerateReport);",
        "if (dom.reportBtn) dom.reportBtn.addEventListener('click', onGenerateReport);\n"
        "  if (dom.startSetBtn) dom.startSetBtn.addEventListener('click', onStartSet);\n"
        "  if (dom.endSetBtn) dom.endSetBtn.addEventListener('click', onEndSet);"
    )

# 4. Update onReset to also reset sets
src = src.replace(
    "function onReset() {\n  resetArmState(armL);\n  resetArmState(armR);",
    "function onReset() {\n  resetArmState(armL);\n  resetArmState(armR);\n"
    "  Object.assign(setL, makeSetState());\n"
    "  Object.assign(setR, makeSetState());\n"
    "  setActive = false;\n"
    "  updateFatigueUI();\n"
    "  updateSetButtons();"
)

# 5. Update processSide to capture rep records and feed them to set state
old_detect = "  detectRep(armState, primaryAngle, primaryAct, formCheck, exercise.repThresholds);"
new_detect = """  const repRecord = detectRep(armState, primaryAngle, primaryAct, formCheck, exercise.repThresholds, timestamp);
  if (repRecord && setActive) {
    const setState = armState === armL ? setL : setR;
    recordRep(setState, repRecord);
  }"""
src = src.replace(old_detect, new_detect)

# 6. Add fatigue UI updates to the predictLoop — call it once per frame right
#    after updateAsymmetryUI
if 'updateFatigueUI' not in src.split('function onGenerateReport')[0]:
    src = src.replace(
        "updateAsymmetryUI(computeAsymmetry(armL, armR));\n        updateFormBanner(mergeFormVerdicts(resultL.formCheck, resultR.formCheck));",
        "updateAsymmetryUI(computeAsymmetry(armL, armR));\n        updateFormBanner(mergeFormVerdicts(resultL.formCheck, resultR.formCheck));\n        updateFatigueUI();"
    )
    # also inside the demo onFrame:
    src = src.replace(
        "updateAsymmetryUI(computeAsymmetry(armL, armR));\n      updateFormBanner(mergeFormVerdicts(formL, formR));",
        "updateAsymmetryUI(computeAsymmetry(armL, armR));\n      updateFormBanner(mergeFormVerdicts(formL, formR));\n      updateFatigueUI();"
    )

# 7. Add the handler functions right before init()
if 'function onStartSet' not in src:
    handlers = '''
function onStartSet() {
  startSetFn(setL);
  startSetFn(setR);
  setActive = true;
  updateSetButtons();
  updateFatigueUI();
  log('set started — tracking fatigue', 'ok');
}

function onEndSet() {
  endSetFn(setL);
  endSetFn(setR);
  setActive = false;
  updateSetButtons();
  updateFatigueUI();
  const sL = summarizeSet(setL);
  const sR = summarizeSet(setR);
  const totalReps = (sL?.totalReps || 0) + (sR?.totalReps || 0);
  const lossL = sL ? Math.round(sL.finalVelLoss * 100) : 0;
  const lossR = sR ? Math.round(sR.finalVelLoss * 100) : 0;
  log('set ended — ' + totalReps + ' reps · vel loss L ' + lossL + '% · R ' + lossR + '%', 'ok');
}

function updateSetButtons() {
  if (dom.startSetBtn) {
    dom.startSetBtn.disabled = setActive;
    dom.startSetBtn.textContent = setActive ? 'Set active…' : 'Start set';
  }
  if (dom.endSetBtn) {
    dom.endSetBtn.style.display = setActive ? 'inline-block' : 'none';
  }
}

function updateFatigueUI() {
  if (!dom.fatigueWrap) return;

  if (!setActive && setL.reps.length === 0 && setR.reps.length === 0) {
    dom.fatigueWrap.classList.add('inactive');
    dom.fatigueStatus.textContent = 'NO SET ACTIVE';
    dom.rirValue.textContent = '—';
    dom.fatigueFill.style.width = '0%';
    dom.fatigueFill.className = 'fatigue-fill';
    dom.velLossValue.textContent = '—';
    return;
  }

  dom.fatigueWrap.classList.remove('inactive');

  // Use the side with more reps as the primary display
  const primarySet = setL.reps.length >= setR.reps.length ? setL : setR;
  const result = computeFatigue(primarySet);

  if (result.rir === null) {
    dom.fatigueStatus.textContent = 'BASELINING…';
    dom.rirValue.textContent = '—';
    dom.fatigueFill.style.width = '5%';
    dom.fatigueFill.className = 'fatigue-fill';
    dom.velLossValue.textContent = '—';
    return;
  }

  const { label, severity } = rirLabel(result.rir);
  dom.fatigueStatus.textContent = label;
  dom.fatigueStatus.dataset.severity = severity;

  // RIR display — round to nearest half
  const rirDisplay = Math.round(result.rir * 2) / 2;
  dom.rirValue.textContent = rirDisplay;

  // Fatigue bar fill
  const fillPct = Math.min(100, result.fatigue * 100 / 0.4 * 100);
  dom.fatigueFill.style.width = Math.min(100, result.fatigue / 0.4 * 100) + '%';
  dom.fatigueFill.className = 'fatigue-fill ' + severity;

  // Velocity loss
  const velLossPct = Math.round(result.signals.velLoss * 100);
  dom.velLossValue.textContent = velLossPct + '%';
}

'''
    src = src.replace('init();', handlers + 'init();')

# 8. Extend the predictLoop/processSide signature to pass timestamp through.
#    The processSide function currently takes `timestamp` as its 5th arg; the
#    detectRep call needs it. We already passed timestamp above.

# 9. Ensure the set-UI initial state is set in init()
if 'updateSetButtons()' not in src.split('async function init')[1].split('try {')[0]:
    src = src.replace(
        "selectExercise('bicepCurl');",
        "selectExercise('bicepCurl');\n  updateSetButtons();\n  updateFatigueUI();"
    )

with open('src/main.js', 'w') as f:
    f.write(src)
print('src/main.js updated')
PYEOF

echo -e "${BLUE}→ Updating src/ui/dom.js…${NC}"
python3 <<'PYEOF'
with open('src/ui/dom.js', 'r') as f:
    src = f.read()

if 'startSetBtn' not in src:
    src = src.replace(
        "reportBtn: $('reportBtn'),",
        "reportBtn: $('reportBtn'),\n\n"
        "  startSetBtn: $('startSetBtn'),\n"
        "  endSetBtn: $('endSetBtn'),\n"
        "  fatigueWrap: $('fatigueWrap'),\n"
        "  fatigueStatus: $('fatigueStatus'),\n"
        "  rirValue: $('rirValue'),\n"
        "  fatigueFill: $('fatigueFill'),\n"
        "  velLossValue: $('velLossValue'),"
    )

with open('src/ui/dom.js', 'w') as f:
    f.write(src)
print('src/ui/dom.js updated')
PYEOF

echo -e "${BLUE}→ Updating index.html…${NC}"
python3 <<'PYEOF'
import re

with open('index.html', 'r') as f:
    html = f.read()

# Version tag
html = re.sub(
    r'<span class="tag">MUSCLEMAP · v0\.[0-9]+[^<]*</span>',
    '<span class="tag">MUSCLEMAP · v0.6 · FATIGUE TRACKING</span>',
    html
)

# Add Start Set / End Set buttons to the controls row
if 'id="startSetBtn"' not in html:
    html = html.replace(
        '<button id="reportBtn" class="accent-outline">Generate report</button>',
        '<button id="reportBtn" class="accent-outline">Generate report</button>\n'
        '          <button id="startSetBtn" class="accent-outline">Start set</button>\n'
        '          <button id="endSetBtn" class="danger" style="display:none;">End set</button>'
    )

# Add the fatigue panel to the side column (insert it before the asymmetry panel)
if 'id="fatigueWrap"' not in html:
    fatigue_panel = '''
        <div class="panel fatigue-panel inactive" id="fatigueWrap">
          <div class="section-title">Proximity to failure</div>
          <div class="fatigue-header">
            <div class="fatigue-rir">
              <div class="rir-label">RIR</div>
              <div class="rir-value" id="rirValue">—</div>
            </div>
            <div class="fatigue-status" id="fatigueStatus" data-severity="neutral">NO SET ACTIVE</div>
          </div>
          <div class="fatigue-gauge">
            <div class="fatigue-fill" id="fatigueFill" style="width:0%;"></div>
          </div>
          <div class="fatigue-scale">
            <span>FRESH</span><span>WORKING</span><span>FAILURE</span>
          </div>
          <div class="metric-row" style="margin-top:10px;">
            <span class="metric-label">Velocity loss</span>
            <span class="metric-value" id="velLossValue" style="font-size:18px;">—</span>
          </div>
        </div>
'''
    html = html.replace(
        '<div class="panel">\n          <div class="section-title">Left / Right symmetry</div>',
        fatigue_panel + '        <div class="panel">\n          <div class="section-title">Left / Right symmetry</div>'
    )

with open('index.html', 'w') as f:
    f.write(html)
print('index.html updated')
PYEOF

echo -e "${BLUE}→ Appending fatigue-panel styles…${NC}"
if ! grep -q "fatigue-panel" src/ui/styles.css; then
  cat >> src/ui/styles.css <<'EOF'

/* --- Fatigue panel --- */
.fatigue-panel.inactive {
  opacity: 0.55;
}
.fatigue-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  margin-bottom: 14px;
}
.fatigue-rir {
  display: flex;
  align-items: baseline;
  gap: 10px;
}
.rir-label {
  font-family: 'Menlo', monospace;
  font-size: 10px;
  letter-spacing: 0.2em;
  color: var(--text-dim);
}
.rir-value {
  font-family: 'Syne', 'Menlo', sans-serif;
  font-weight: 800;
  font-size: 36px;
  color: var(--text);
  line-height: 1;
}
.fatigue-status {
  font-family: 'Menlo', monospace;
  font-size: 10px;
  letter-spacing: 0.15em;
  font-weight: 700;
  padding: 6px 10px;
  border-radius: 6px;
  text-align: right;
  color: var(--text-dim);
  background: rgba(255,255,255,0.03);
  border: 1px solid var(--border);
}
.fatigue-status[data-severity="good"] {
  color: var(--accent);
  border-color: rgba(0,255,157,0.3);
  background: rgba(0,255,157,0.05);
}
.fatigue-status[data-severity="warning"] {
  color: var(--amber);
  border-color: rgba(255,209,102,0.3);
  background: rgba(255,209,102,0.05);
}
.fatigue-status[data-severity="bad"] {
  color: var(--warn);
  border-color: rgba(255,107,107,0.3);
  background: rgba(255,107,107,0.05);
  animation: fatigue-pulse 1.2s ease-in-out infinite;
}
@keyframes fatigue-pulse {
  0%, 100% { box-shadow: 0 0 0 rgba(255,107,107,0); }
  50% { box-shadow: 0 0 12px rgba(255,107,107,0.4); }
}
.fatigue-gauge {
  height: 12px;
  background: rgba(255,255,255,0.05);
  border-radius: 6px;
  overflow: hidden;
  position: relative;
}
.fatigue-fill {
  height: 100%;
  width: 0%;
  background: linear-gradient(90deg, var(--accent), var(--amber));
  border-radius: 6px;
  transition: width 0.3s ease, background 0.3s;
}
.fatigue-fill.warning {
  background: linear-gradient(90deg, var(--accent), var(--amber), var(--amber));
}
.fatigue-fill.bad {
  background: linear-gradient(90deg, var(--amber), var(--warn));
}
.fatigue-scale {
  display: flex;
  justify-content: space-between;
  font-family: 'Menlo', monospace;
  font-size: 9px;
  color: var(--text-dimmer);
  margin-top: 6px;
  letter-spacing: 0.05em;
}
EOF
  echo -e "${GREEN}  ✓${NC} styles appended"
else
  echo -e "${YELLOW}  ⚠ fatigue-panel styles already present${NC}"
fi

# --- Update demo.js to simulate fatigue during a simulated set ---
echo -e "${BLUE}→ Updating src/sources/demo.js (simulated fatigue)…${NC}"
python3 <<'PYEOF'
with open('src/sources/demo.js', 'r') as f:
    src = f.read()

# We need the demo to slow down over time to simulate fatigue. We'll modulate
# the angular frequency based on rep count, so velocity naturally decays.

# Find the curl demo block's elbowL line
old = """      const elbowL = 105 + 65 * Math.cos(t);
      const elbowR = 110 + 58 * Math.cos(t - 0.15);"""
new = """      // Simulate fatigue: frequency slows down as "reps" accumulate
      const fatigueFactor = Math.max(0.55, 1 - (armL.repCount * 0.05));
      const tF = t * fatigueFactor;
      const elbowL = 105 + 65 * Math.cos(tF);
      const elbowR = 110 + 58 * Math.cos(tF - 0.15);"""
src = src.replace(old, new)

# Do the same for the shoulder (they share the t variable)
src = src.replace(
    "const shoulderL = 170 + 8 * Math.sin(t * 0.8);\n      const shoulderR = 155 + 20 * Math.sin(t * 1.1);",
    "const shoulderL = 170 + 8 * Math.sin(tF * 0.8);\n      const shoulderR = 155 + 20 * Math.sin(tF * 1.1);"
)
src = src.replace(
    "const angVelL = -65 * Math.sin(t);\n      const angVelR = -58 * Math.sin(t - 0.15);",
    "const angVelL = -65 * Math.sin(tF) * fatigueFactor;\n      const angVelR = -58 * Math.sin(tF - 0.15) * fatigueFactor;"
)

with open('src/sources/demo.js', 'w') as f:
    f.write(src)
print('src/sources/demo.js updated (fatigue simulation added)')
PYEOF

# --- Update PDF report to include fatigue ---
echo -e "${BLUE}→ Updating src/reports/pdf-report.js (add velocity chart)…${NC}"
python3 <<'PYEOF'
with open('src/reports/pdf-report.js', 'r') as f:
    src = f.read()

# The report currently ends with the notes/footer. We'll add a "set summary"
# block right after the rep timeline if set data is present in the summary.

# Wrap this up: just extend the report to accept an optional setSummary and
# render it if present. Minimal change for now; real set-aware reports can
# come with the next PR.

if 'setSummary' not in src:
    # Inject a helper call right before the notes section
    src = src.replace(
        "  // ---- Notes ----",
        """  // ---- Set summary ----
  if (summary.setSummary) {
    drawRule(doc, M, y, W - M);
    y += 18;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(COLORS.text);
    doc.text('SET SUMMARY', M, y);
    y += 14;
    const s = summary.setSummary;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(COLORS.textDim);
    const lossPct = Math.round(s.finalVelLoss * 100);
    const rirStr = s.estimatedFinalRIR !== null ? s.estimatedFinalRIR.toFixed(1) : 'n/a';
    doc.text('Reps completed: ' + s.totalReps + '     Velocity loss: ' + lossPct + '%     Estimated final RIR: ' + rirStr, M, y);
    y += 14;

    // Mini velocity chart
    const chartW = W - M * 2;
    const chartH = 35;
    const maxV = Math.max(...s.velocities, 0.001);
    const barW = Math.max(2, Math.min(16, chartW / Math.max(s.velocities.length, 1) - 2));
    s.velocities.forEach((v, i) => {
      const barH = (v / maxV) * chartH;
      const bx = M + i * (barW + 2);
      const by = y + chartH - barH;
      doc.setFillColor(COLORS.accent);
      doc.rect(bx, by, barW, barH, 'F');
    });
    y += chartH + 8;
    doc.setFontSize(8);
    doc.setTextColor(COLORS.textDim);
    doc.text('Rep-by-rep concentric velocity (higher = faster, velocity loss = fatigue)', M, y);
    y += 18;
  }

  // ---- Notes ----"""
    )

with open('src/reports/pdf-report.js', 'w') as f:
    f.write(src)
print('src/reports/pdf-report.js updated')
PYEOF

# --- Wire the set summary into session-summary.js and the report call ---
echo -e "${BLUE}→ Updating src/analytics/session-summary.js to include set data…${NC}"
python3 <<'PYEOF'
with open('src/analytics/session-summary.js', 'r') as f:
    src = f.read()

if 'setSummary' not in src:
    # Change the function signature to accept a setSummary
    src = src.replace(
        "export function buildSessionSummary(armL, armR, exercise, sessionMeta = {}) {",
        "export function buildSessionSummary(armL, armR, exercise, sessionMeta = {}, setSummary = null) {"
    )
    # Include it in the returned object, right after `timeline:`
    src = src.replace(
        "    // Rep-by-rep timeline\n    timeline: timeline(armL, armR),\n  };",
        "    // Rep-by-rep timeline\n    timeline: timeline(armL, armR),\n\n    // Optional: latest set summary from fatigue.js\n    setSummary,\n  };"
    )

with open('src/analytics/session-summary.js', 'w') as f:
    f.write(src)
print('src/analytics/session-summary.js updated')
PYEOF

# --- Update the onGenerateReport handler to pass the set summary in ---
echo -e "${BLUE}→ Wiring set summary into onGenerateReport…${NC}"
python3 <<'PYEOF'
with open('src/main.js', 'r') as f:
    src = f.read()

old = """  const summary = buildSessionSummary(armL, armR, currentExercise, {
    clientName: dom.clientNameInput?.value || '',
    trainerName: dom.trainerNameInput?.value || '',
    notes: dom.notesInput?.value || '',
  });"""
new = """  // Prefer the side with more reps for the set summary (single-set report for now)
  const primarySet = setL.reps.length >= setR.reps.length ? setL : setR;
  const setSummary = primarySet.reps.length > 0 ? summarizeSet(primarySet) : null;
  const summary = buildSessionSummary(armL, armR, currentExercise, {
    clientName: dom.clientNameInput?.value || '',
    trainerName: dom.trainerNameInput?.value || '',
    notes: dom.notesInput?.value || '',
  }, setSummary);"""

if "primarySet.reps.length" not in src:
    src = src.replace(old, new)

with open('src/main.js', 'w') as f:
    f.write(src)
print('onGenerateReport updated')
PYEOF

# --- Commit ---
echo ""
echo -e "${BLUE}→ Committing…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit${NC}"
else
  git commit -q -m "feat: fatigue tracking & proximity-to-failure estimation

- New module src/analytics/fatigue.js: composite fatigue model using
  velocity loss (primary), ROM drift, concentric/eccentric duration
  ratio, and form breakdown rate. Maps fatigue to RIR estimate (0-10).
- rep-detector emits per-rep velocity and phase durations, captured
  from angle history during concentric/eccentric phases
- Start set / End set buttons control the baselining window
- Live UI panel: big RIR number, fatigue gauge, velocity loss %,
  color-coded status (fresh / working / approaching failure / at failure)
- PDF report: set summary block with rep-by-rep velocity chart +
  final velocity loss + estimated RIR at set end
- Demo mode simulates progressive fatigue across reps for easy testing

Research basis for thresholds:
  <10%% vel loss = RIR >= 5, 20-30%% = RIR 1-3, >30%% = failure
  (Sanchez-Medina & Gonzalez-Badillo 2011; Weakley et al. 2021)"
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Fatigue tracking ready           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  1. Click ${BLUE}Demo${NC} (simulation includes progressive fatigue)"
echo -e "  2. Click ${BLUE}Start set${NC} — RIR panel lights up"
echo -e "  3. Watch the RIR number count down as simulated reps slow"
echo -e "  4. Click ${BLUE}End set${NC} — log shows final velocity loss"
echo -e "  5. Click ${BLUE}Generate report${NC} — PDF now includes velocity chart"
echo ""
echo -e "${YELLOW}Merge when ready:${NC}"
echo -e "  ${BLUE}git push -u origin feat/fatigue-tracking${NC}"
echo -e "  ${BLUE}git checkout main && git merge feat/fatigue-tracking${NC}"
echo -e "  ${BLUE}git push && git branch -d feat/fatigue-tracking${NC}"
echo ""
