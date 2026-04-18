const RANK = { good: 0, warning: 1, bad: 2 };

export function detectRep(state, angle, primaryAct, formCheck, thresholds) {
  const FLEX_THR = thresholds?.flex ?? 80;
  const EXT_THR  = thresholds?.ext  ?? 150;

  state.minAngleThisRep = Math.min(state.minAngleThisRep, angle);
  state.maxAngleThisRep = Math.max(state.maxAngleThisRep, angle);
  state.peakBicepThisRep = Math.max(state.peakBicepThisRep, primaryAct);

  if (formCheck && RANK[formCheck.verdict] > RANK[state.worstFormThisRep]) {
    state.worstFormThisRep = formCheck.verdict;
  }

  if (state.currentPhase === 'neutral' && angle > EXT_THR) {
    state.currentPhase = 'down';
    startNewRep(state, angle);
  } else if (state.currentPhase === 'down' && angle < FLEX_THR) {
    state.currentPhase = 'up';
  } else if (state.currentPhase === 'up' && angle > EXT_THR) {
    state.repCount++;
    state.repPeaks.push(state.peakBicepThisRep);
    state.repROMs.push([state.minAngleThisRep, state.maxAngleThisRep]);
    state.repFormFlags.push(state.worstFormThisRep);
    state.currentPhase = 'down';
    startNewRep(state, angle);
    return true;
  }
  return false;
}

function startNewRep(state, angle) {
  state.minAngleThisRep = angle;
  state.maxAngleThisRep = angle;
  state.peakBicepThisRep = 0;
  state.worstFormThisRep = 'good';
}

export function isAtBottom(state, angle, thresholds) {
  const FLEX_THR = thresholds?.flex ?? 80;
  return state.currentPhase === 'up' && angle < FLEX_THR + 15;
}
