let demoRunning = false;

export function runDemo(exercise, armL, armR, { onFrame, isRunning }) {
  demoRunning = true;
  let t = 0;

  const tick = () => {
    if (!isRunning() || !demoRunning) return;
    t += 0.03;

    const elbowL = 105 + 65 * Math.cos(t);
    const shoulderL = 170 + 8 * Math.sin(t * 0.8);
    const elbowR = 110 + 58 * Math.cos(t - 0.15);
    const shoulderR = 155 + 20 * Math.sin(t * 1.1);

    const now = performance.now();
    const angVelL = -65 * Math.sin(t);
    const angVelR = -58 * Math.sin(t - 0.15);
    const actsL = exercise.estimateActivations(elbowL, shoulderL, angVelL);
    const actsR = exercise.estimateActivations(elbowR, shoulderR, angVelR);
    actsR.bicep *= 0.82;
    actsR.deltoid *= 0.9;
    actsR.forearm *= 0.88;

    pushAngleHistory(armL, elbowL, now);
    pushAngleHistory(armR, elbowR, now);

    const formL = exercise.checkForm({ elbowAngle: elbowL, shoulderAngle: shoulderL, phase: armL.currentPhase });
    const formR = exercise.checkForm({ elbowAngle: elbowR, shoulderAngle: shoulderR, phase: armR.currentPhase });

    updateRepFromDemo(armL, elbowL, actsL.bicep, formL);
    updateRepFromDemo(armR, elbowR, actsR.bicep, formR);

    onFrame(actsL, actsR, elbowL, elbowR, formL, formR);
    setTimeout(tick, 30);
  };
  tick();
}

export function stopDemo() { demoRunning = false; }

function pushAngleHistory(state, angle, now) {
  state.angleHistory.push(angle);
  state.angleTimestamps.push(now);
  if (state.angleHistory.length > 10) {
    state.angleHistory.shift();
    state.angleTimestamps.shift();
  }
}

const RANK = { good: 0, warning: 1, bad: 2 };
function updateRepFromDemo(state, angle, bicepAct, formCheck) {
  const FLEX_THR = 80, EXT_THR = 150;
  state.minAngleThisRep = Math.min(state.minAngleThisRep, angle);
  state.maxAngleThisRep = Math.max(state.maxAngleThisRep, angle);
  state.peakBicepThisRep = Math.max(state.peakBicepThisRep, bicepAct);
  if (formCheck && RANK[formCheck.verdict] > RANK[state.worstFormThisRep]) {
    state.worstFormThisRep = formCheck.verdict;
  }
  if (state.currentPhase === 'neutral' && angle > EXT_THR) {
    state.currentPhase = 'down';
    reset(state, angle);
  } else if (state.currentPhase === 'down' && angle < FLEX_THR) {
    state.currentPhase = 'up';
  } else if (state.currentPhase === 'up' && angle > EXT_THR) {
    state.repCount++;
    state.repPeaks.push(state.peakBicepThisRep);
    state.repROMs.push([state.minAngleThisRep, state.maxAngleThisRep]);
    state.repFormFlags.push(state.worstFormThisRep);
    state.currentPhase = 'down';
    reset(state, angle);
  }
}
function reset(state, angle) {
  state.minAngleThisRep = angle;
  state.maxAngleThisRep = angle;
  state.peakBicepThisRep = 0;
  state.worstFormThisRep = 'good';
}
