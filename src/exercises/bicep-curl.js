import { LANDMARKS } from '../pose/landmarks.js';
import { angleBetween } from '../biomechanics/angles.js';
import { bicepCurlActivations } from '../biomechanics/activation.js';
import { runFormRules } from '../biomechanics/form-rules.js';

const SHOULDER_SWING_MAX = 25;
const SHOULDER_SWING_BAD = 40;
const HYPEREXTENSION_MAX = 175;

const rules = [
  ({ shoulderAngle, phase }) => {
    if (phase !== 'up') return null;
    const shoulderFlex = 180 - shoulderAngle;
    if (shoulderFlex > SHOULDER_SWING_BAD) {
      return { verdict: 'bad', priority: 10, cue: 'Stop swinging — pin your elbows to your sides.' };
    }
    if (shoulderFlex > SHOULDER_SWING_MAX) {
      return { verdict: 'warning', priority: 7, cue: 'Keep your shoulder still. Isolate the biceps.' };
    }
    return null;
  },

  ({ elbowAngle, phase }) => {
    if (phase !== 'up') return null;
    if (elbowAngle > 95 && elbowAngle < 110) {
      return { verdict: 'warning', priority: 5, cue: 'Curl higher — bring the weight all the way up.' };
    }
    return null;
  },

  ({ elbowAngle, phase }) => {
    if (phase !== 'down') return null;
    if (elbowAngle > 100 && elbowAngle < 130) {
      return { verdict: 'warning', priority: 4, cue: 'Extend fully at the bottom — full range of motion.' };
    }
    return null;
  },

  ({ elbowAngle }) => {
    if (elbowAngle > HYPEREXTENSION_MAX) {
      return { verdict: 'warning', priority: 3, cue: 'Avoid fully locking your elbow — keep a slight bend.' };
    }
    return null;
  }
];

export const bicepCurl = {
  id: 'bicepCurl',
  name: 'Bicep Curl',

  getKeypoints(landmarks, side) {
    const k = side === 'left'
      ? { shoulder: LANDMARKS.L_SHOULDER, elbow: LANDMARKS.L_ELBOW, wrist: LANDMARKS.L_WRIST, hip: LANDMARKS.L_HIP }
      : { shoulder: LANDMARKS.R_SHOULDER, elbow: LANDMARKS.R_ELBOW, wrist: LANDMARKS.R_WRIST, hip: LANDMARKS.R_HIP };

    const s = landmarks[k.shoulder];
    const e = landmarks[k.elbow];
    const w = landmarks[k.wrist];
    const h = landmarks[k.hip];

    if (!s || !e || !w || !h) return null;
    if (s.visibility < 0.5 || e.visibility < 0.5 || w.visibility < 0.5) return null;

    return {
      shoulder: { x: s.x, y: s.y },
      elbow: { x: e.x, y: e.y },
      wrist: { x: w.x, y: w.y },
      hip: { x: h.x, y: h.y },
    };
  },

  computeAngles(kp) {
    return {
      elbowAngle: angleBetween(kp.shoulder, kp.elbow, kp.wrist),
      shoulderAngle: angleBetween(kp.hip, kp.shoulder, kp.elbow),
    };
  },

  estimateActivations: bicepCurlActivations,

  checkForm(context) {
    return runFormRules(rules, context);
  }
};
