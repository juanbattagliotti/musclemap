// =========================================================================
// Build a session summary from the per-arm state.
// This is the single source of truth for what appears in reports.
// =========================================================================

export function buildSessionSummary(armL, armR, exercise, sessionMeta = {}, setSummary = null) {
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

    // Optional: latest set summary from fatigue.js
    setSummary,
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
