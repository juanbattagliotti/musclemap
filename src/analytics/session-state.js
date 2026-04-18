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
