import { LANDMARKS } from '../pose/landmarks.js';
import { angleBetween } from '../biomechanics/angles.js';
import { bicepCurlActivations } from '../biomechanics/activation.js';
import { runFormRules } from '../biomechanics/form-rules.js';

const SHOULDER_LIFT_WARN = 25;   // degrees of upper-arm lift from torso
const SHOULDER_LIFT_BAD  = 40;
const HYPEREXTENSION_MAX = 175;

const rules = [
  ({ shoulderLift, phase }) => {
    if (phase !== 'up') return null;
    if (shoulderLift > SHOULDER_LIFT_BAD) {
      return { verdict: 'bad', priority: 10, cue: 'Stop swinging — pin your elbows to your sides.' };
    }
    if (shoulderLift > SHOULDER_LIFT_WARN) {
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
      shoulder: { x: s.x, y: s.y, visibility: s.visibility },
      elbow:    { x: e.x, y: e.y, visibility: e.visibility },
      wrist:    { x: w.x, y: w.y, visibility: w.visibility },
      hip:      { x: h.x, y: h.y, visibility: h.visibility },
    };
  },

  computeAngles(kp) {
    const elbowAngle = angleBetween(kp.shoulder, kp.elbow, kp.wrist);

    // --- Shoulder lift, the fixed way ---
    //
    // Old approach: angleBetween(hip, shoulder, elbow) — sensitive to 2D
    // foreshortening when arms are near the torso. In that geometry the
    // three points are nearly collinear, so tiny hip jitter blows up the
    // angle.
    //
    // New approach: measure how much the upper-arm vector (shoulder->elbow)
    // deviates from the torso vector (shoulder->hip). The torso vector is
    // long and stable; the deviation is what we actually care about for
    // "is the shoulder flexing forward/up?"
    //
    // If hip confidence is low, fall back to pure vertical as the reference
    // (downward in image coords = +y).

    const torsoOK = kp.hip.visibility > 0.5;
    // Reference vector: shoulder -> hip (down-the-torso)
    const refX = torsoOK ? (kp.hip.x - kp.shoulder.x) : 0;
    const refY = torsoOK ? (kp.hip.y - kp.shoulder.y) : 1;  // +y = downward in image coords

    // Upper-arm vector: shoulder -> elbow
    const armX = kp.elbow.x - kp.shoulder.x;
    const armY = kp.elbow.y - kp.shoulder.y;

    // Angle between the two vectors
    const refLen = Math.hypot(refX, refY);
    const armLen = Math.hypot(armX, armY);
    let shoulderLift = 0;
    if (refLen > 0 && armLen > 0) {
      const cos = (refX * armX + refY * armY) / (refLen * armLen);
      shoulderLift = Math.acos(Math.max(-1, Math.min(1, cos))) * 180 / Math.PI;
    }
    // shoulderLift = 0 when the upper arm points exactly along the torso
    // (arm hanging straight down), grows as the arm lifts in any direction.

    // Preserve the legacy "shoulderAngle" field for anything that still
    // reads it, but compute it from the new measurement:
    // shoulderAngle = 180 - shoulderLift (i.e. 180 = arm hanging, 90 = arm horizontal)
    const shoulderAngle = 180 - shoulderLift;

    return {
      elbowAngle,
      shoulderAngle,   // legacy slot (still used by activation function)
      shoulderLift,    // new, preferred field for form rules
    };
  },

  estimateActivations: bicepCurlActivations,

  checkForm(context) {
    return runFormRules(rules, context);
  }
};
