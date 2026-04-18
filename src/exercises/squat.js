import { LANDMARKS } from '../pose/landmarks.js';
import { angleBetween } from '../biomechanics/angles.js';
import { squatActivations } from '../biomechanics/activation.js';
import { runFormRules } from '../biomechanics/form-rules.js';

const DEPTH_SHALLOW = 135;
const VALGUS_WARNING = 0.12;
const VALGUS_BAD = 0.20;
const FORWARD_LEAN_WARNING = 35;
const FORWARD_LEAN_BAD = 55;
const ASYMMETRY_WARNING = 15;
const STANCE_NARROW = 0.6;
const STANCE_WIDE = 2.0;

const rules = [
  ({ kneeAngle, atBottom }) => {
    if (!atBottom) return null;
    if (kneeAngle > DEPTH_SHALLOW) {
      return { verdict: 'warning', priority: 8, cue: 'Squat deeper — aim for thighs parallel to the floor.' };
    }
    return null;
  },
  ({ valgusScore, phase }) => {
    if (phase === 'neutral') return null;
    if (valgusScore > VALGUS_BAD) {
      return { verdict: 'bad', priority: 10, cue: 'Push your knees OUT — stop them caving inward.' };
    }
    if (valgusScore > VALGUS_WARNING) {
      return { verdict: 'warning', priority: 9, cue: 'Watch your knees — drive them slightly outward, tracking your toes.' };
    }
    return null;
  },
  ({ trunkLean, phase }) => {
    if (phase === 'neutral') return null;
    if (trunkLean > FORWARD_LEAN_BAD) {
      return { verdict: 'bad', priority: 9, cue: 'Chest up! Too much forward lean — engage your core.' };
    }
    if (trunkLean > FORWARD_LEAN_WARNING) {
      return { verdict: 'warning', priority: 6, cue: 'Keep your chest proud — reduce the forward lean.' };
    }
    return null;
  },
  ({ kneeAsymmetry, phase }) => {
    if (phase === 'neutral') return null;
    if (kneeAsymmetry > ASYMMETRY_WARNING) {
      return { verdict: 'warning', priority: 7, cue: 'You\'re shifting — load both legs evenly.' };
    }
    return null;
  },
  ({ stanceRatio, phase }) => {
    if (phase !== 'neutral') return null;
    if (stanceRatio < STANCE_NARROW) {
      return { verdict: 'warning', priority: 3, cue: 'Widen your stance — feet about shoulder-width apart.' };
    }
    if (stanceRatio > STANCE_WIDE) {
      return { verdict: 'warning', priority: 3, cue: 'Stance is very wide — narrow it for a standard squat.' };
    }
    return null;
  },
];

export const squat = {
  id: 'squat',
  name: 'Squat',

  getKeypoints(landmarks, side) {
    const pick = (idx) => {
      const p = landmarks[idx];
      if (!p || p.visibility < 0.4) return null;
      return { x: p.x, y: p.y };
    };

    const L_SHOULDER = pick(LANDMARKS.L_SHOULDER);
    const R_SHOULDER = pick(LANDMARKS.R_SHOULDER);
    const L_HIP = pick(LANDMARKS.L_HIP);
    const R_HIP = pick(LANDMARKS.R_HIP);
    const L_KNEE = pick(LANDMARKS.L_KNEE);
    const R_KNEE = pick(LANDMARKS.R_KNEE);
    const L_ANKLE = pick(LANDMARKS.L_ANKLE);
    const R_ANKLE = pick(LANDMARKS.R_ANKLE);

    if (!L_HIP || !R_HIP || !L_KNEE || !R_KNEE || !L_ANKLE || !R_ANKLE) return null;
    if (!L_SHOULDER || !R_SHOULDER) return null;

    if (side === 'left') {
      return {
        shoulder: L_SHOULDER, hip: L_HIP, knee: L_KNEE, ankle: L_ANKLE,
        otherHip: R_HIP, otherKnee: R_KNEE, otherAnkle: R_ANKLE,
        midShoulder: midpoint(L_SHOULDER, R_SHOULDER),
        midHip: midpoint(L_HIP, R_HIP),
      };
    }
    return {
      shoulder: R_SHOULDER, hip: R_HIP, knee: R_KNEE, ankle: R_ANKLE,
      otherHip: L_HIP, otherKnee: L_KNEE, otherAnkle: L_ANKLE,
      midShoulder: midpoint(L_SHOULDER, R_SHOULDER),
      midHip: midpoint(L_HIP, R_HIP),
    };
  },

  computeAngles(kp) {
    const kneeAngle = angleBetween(kp.hip, kp.knee, kp.ankle);
    const hipAngle = angleBetween(kp.shoulder, kp.hip, kp.knee);

    const spineVec = {
      x: kp.midShoulder.x - kp.midHip.x,
      y: kp.midShoulder.y - kp.midHip.y
    };
    const trunkLeanRad = Math.atan2(Math.abs(spineVec.x), Math.abs(spineVec.y));
    const trunkLean = trunkLeanRad * 180 / Math.PI;

    const leftValgus = lateralDeviation(kp.otherHip, kp.otherAnkle, kp.otherKnee);
    const rightValgus = lateralDeviation(kp.hip, kp.ankle, kp.knee);
    const valgusScore = Math.max(leftValgus.inward, rightValgus.inward);

    const leftKneeAngle = angleBetween(kp.otherHip, kp.otherKnee, kp.otherAnkle);
    const kneeAsymmetry = Math.abs(kneeAngle - leftKneeAngle);

    const ankleDist = dist(kp.ankle, kp.otherAnkle);
    const hipDist = dist(kp.hip, kp.otherHip);
    const stanceRatio = hipDist > 0 ? ankleDist / hipDist : 1.0;

    return {
      elbowAngle: kneeAngle,
      shoulderAngle: hipAngle,
      kneeAngle,
      hipAngle,
      trunkLean,
      valgusScore,
      kneeAsymmetry,
      stanceRatio,
    };
  },

  estimateActivations(kneeAngle, hipAngle, angVel) {
    return squatActivations(kneeAngle, hipAngle, 0, angVel);
  },

  estimateActivationsFull(kneeAngle, hipAngle, trunkLean, angVel) {
    return squatActivations(kneeAngle, hipAngle, trunkLean, angVel);
  },

  checkForm(context) {
    return runFormRules(rules, context);
  },

  getRepAngle(kneeAngle) { return kneeAngle; },

  repThresholds: {
    flex: 110,
    ext: 165,
  }
};

function midpoint(a, b) {
  return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
}
function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }

function lateralDeviation(hip, ankle, knee) {
  const dx = ankle.x - hip.x;
  const dy = ankle.y - hip.y;
  const lenSq = dx*dx + dy*dy;
  if (lenSq === 0) return { inward: 0, outward: 0 };
  const cross = (knee.x - hip.x) * dy - (knee.y - hip.y) * dx;
  const normalizedSigned = cross / Math.sqrt(lenSq);
  const magNorm = Math.abs(normalizedSigned) / Math.sqrt(lenSq);
  return { inward: magNorm, outward: magNorm };
}
