export function makeArmState() {
  return {
    angleHistory: [],
    angleTimestamps: [],
    repCount: 0,
    repPeaks: [],
    repROMs: [],
    repFormFlags: [],
    currentPhase: 'neutral',
    minAngleThisRep: 180,
    maxAngleThisRep: 0,
    peakBicepThisRep: 0,
    worstFormThisRep: 'good',
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

  return activationFn(elbowAngle, shoulderAngle, angVel);
}
