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
