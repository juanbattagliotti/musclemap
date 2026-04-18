let demoRunning = false;

export function runDemo(exercise, armL, armR, { onFrame, isRunning }) {
  demoRunning = true;
  let t = 0;

  const tick = () => {
    if (!isRunning() || !demoRunning) return;
    t += 0.03;

    let primaryL, primaryR, secondaryL, secondaryR;
    let actsL, actsR;
    let formContextExtrasL, formContextExtrasR;

    if (exercise.id === 'squat') {
      const kneeL = 135 + 45 * Math.cos(t);
      const kneeR = 138 + 42 * Math.cos(t - 0.1);
      const hipL = 150 + 50 * Math.cos(t);
      const hipR = 152 + 48 * Math.cos(t - 0.1);
      const trunkLean = 20 + 15 * Math.sin(t);
      const valgus = kneeL < 110 ? 0.15 : 0.05;

      const angVelL = -45 * Math.sin(t);
      const angVelR = -42 * Math.sin(t - 0.1);

      actsL = exercise.estimateActivationsFull(kneeL, hipL, trunkLean, angVelL);
      actsR = exercise.estimateActivationsFull(kneeR, hipR, trunkLean, angVelR);

      primaryL = kneeL; primaryR = kneeR;
      secondaryL = hipL; secondaryR = hipR;
      formContextExtrasL = { trunkLean, valgusScore: valgus, kneeAsymmetry: Math.abs(kneeL - kneeR), stanceRatio: 1.2 };
      formContextExtrasR = formContextExtrasL;
    } else {
      const elbowL = 105 + 65 * Math.cos(t);
      const elbowR = 110 + 58 * Math.cos(t - 0.15);
      const shoulderL = 170 + 8 * Math.sin(t * 0.8);
      const shoulderR = 155 + 20 * Math.sin(t * 1.1);

      const angVelL = -65 * Math.sin(t);
      const angVelR = -58 * Math.sin(t - 0.15);
      actsL = exercise.estimateActivations(elbowL, shoulderL, angVelL);
      actsR = exercise.estimateActivations(elbowR, shoulderR, angVelR);
      actsR.bicep *= 0.82;
      actsR.deltoid *= 0.9;
      actsR.forearm *= 0.88;

      primaryL = elbowL; primaryR = elbowR;
      secondaryL = shoulderL; secondaryR = shoulderR;
      formContextExtrasL = {};
      formContextExtrasR = {};
    }

    const now = performance.now();
    pushAngleHistory(armL, primaryL, now);
    pushAngleHistory(armR, primaryR, now);

    const formL = exercise.checkForm({
      elbowAngle: primaryL, kneeAngle: primaryL,
      shoulderAngle: secondaryL, hipAngle: secondaryL,
      shoulderLift: Math.max(0, 180 - secondaryL),
      phase: armL.currentPhase,
      atBottom: armL.currentPhase === 'up' && primaryL < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasL,
    });
    const formR = exercise.checkForm({
      elbowAngle: primaryR, kneeAngle: primaryR,
      shoulderAngle: secondaryR, hipAngle: secondaryR,
      shoulderLift: Math.max(0, 180 - secondaryR),
      phase: armR.currentPhase,
      atBottom: armR.currentPhase === 'up' && primaryR < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasR,
    });

    const primaryMuscleKey = exercise.id === 'squat' ? 'quads' : 'bicep';
    updateRepFromDemo(armL, primaryL, actsL[primaryMuscleKey] || 0, formL, exercise.repThresholds);
    updateRepFromDemo(armR, primaryR, actsR[primaryMuscleKey] || 0, formR, exercise.repThresholds);

    onFrame(actsL, actsR, primaryL, primaryR, formL, formR);
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
function updateRepFromDemo(state, angle, primaryAct, formCheck, thresholds) {
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
    resetRep(state, angle);
  } else if (state.currentPhase === 'down' && angle < FLEX_THR) {
    state.currentPhase = 'up';
  } else if (state.currentPhase === 'up' && angle > EXT_THR) {
    state.repCount++;
    state.repPeaks.push(state.peakBicepThisRep);
    state.repROMs.push([state.minAngleThisRep, state.maxAngleThisRep]);
    state.repFormFlags.push(state.worstFormThisRep);
    state.currentPhase = 'down';
    resetRep(state, angle);
  }
}
function resetRep(state, angle) {
  state.minAngleThisRep = angle;
  state.maxAngleThisRep = angle;
  state.peakBicepThisRep = 0;
  state.worstFormThisRep = 'good';
}
