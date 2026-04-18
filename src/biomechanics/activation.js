import { clamp } from './angles.js';

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
