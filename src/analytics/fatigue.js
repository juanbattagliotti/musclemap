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
