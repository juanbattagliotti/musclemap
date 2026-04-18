import { clamp } from './angles.js';

// =========================================================================
// BICEP CURL activation model
// =========================================================================
export function bicepCurlActivations(elbowAngle, shoulderAngle, angVel) {
  // Biceps
  const flexion = clamp((180 - elbowAngle) / 140, 0, 1);
  const mechanical = Math.exp(-Math.pow((elbowAngle - 95) / 45, 2));
  const concentric = angVel < 0 ? 1.0 : 0.6;
  const bicep = clamp((0.55 * flexion + 0.5 * mechanical) * concentric, 0, 1);

  // Anterior deltoid
  //
  // shoulderAngle = 180 when the arm is hanging along the torso, smaller
  // as the arm lifts forward. A clean curl keeps the arm close to the
  // torso (~165-175°), so shoulder flex should be small.
  //
  // Old scale: (180 - shoulderAngle) / 60 — saturated at just 60° of lift,
  //   which combined with noisy hip landmarks made deltoid stick near max.
  //
  // New scale: (180 - shoulderAngle) / 90 — needs 90° of lift (arm
  //   horizontal) to saturate. Plus a higher deadzone so small jitter
  //   doesn't contribute.
  const rawLift = Math.max(0, 180 - shoulderAngle);
  const deadzone = 10;                            // degrees ignored as noise
  const effectiveLift = Math.max(0, rawLift - deadzone);
  const shoulderFlex = clamp(effectiveLift / 90, 0, 1);

  // Resting tone ~15%, full flexion ~75% (anterior delt isn't fully on
  // during a pure curl — it's a stabilizer).
  const deltoid = clamp(0.15 + 0.6 * shoulderFlex, 0, 1);

  // Forearm flexors
  const forearm = clamp(0.25 + 0.6 * flexion, 0, 1);

  return { bicep, deltoid, forearm };
}

// =========================================================================
// SQUAT activation model (unchanged)
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
