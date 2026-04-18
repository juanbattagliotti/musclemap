import { clamp } from './angles.js';

// =========================================================================
// BICEP CURL activation model
// =========================================================================
export function bicepCurlActivations(elbowAngle, shoulderAngle, angVel) {
  const flexion = clamp((180 - elbowAngle) / 140, 0, 1);
  const mechanical = Math.exp(-Math.pow((elbowAngle - 95) / 45, 2));
  const concentric = angVel < 0 ? 1.0 : 0.6;
  const bicep = clamp((0.55 * flexion + 0.5 * mechanical) * concentric, 0, 1);

  const shoulderFlex = clamp((180 - shoulderAngle) / 60, 0, 1);
  const deltoid = clamp(0.2 + 0.6 * shoulderFlex, 0, 1);
  const forearm = clamp(0.25 + 0.6 * flexion, 0, 1);

  return { bicep, deltoid, forearm };
}

// =========================================================================
// SQUAT activation model
// =========================================================================
export function squatActivations(kneeAngle, hipAngle, trunkLean, angVel) {
  const kneeFlex = clamp((180 - kneeAngle) / 110, 0, 1);
  const hipFlex = clamp((180 - hipAngle) / 90, 0, 1);

  const concentric = angVel > 0 ? 1.0 : 0.65;

  const quadMechanical = Math.exp(-Math.pow((kneeAngle - 100) / 40, 2));
  const quads = clamp((0.5 * kneeFlex + 0.6 * quadMechanical) * concentric, 0, 1);

  const glutes = clamp((0.3 + 0.7 * hipFlex) * concentric, 0, 1);

  const hamEccentric = angVel < 0 ? 1.0 : 0.7;
  const hamstrings = clamp((0.2 + 0.4 * hipFlex) * hamEccentric, 0, 1);

  const leanNorm = clamp(trunkLean / 45, 0, 1);
  const erectors = clamp(0.25 + 0.6 * leanNorm, 0, 1);

  return { quads, glutes, hamstrings, erectors };
}
