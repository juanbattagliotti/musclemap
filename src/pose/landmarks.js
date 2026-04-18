export const LANDMARKS = {
  NOSE: 0,
  L_SHOULDER: 11, R_SHOULDER: 12,
  L_ELBOW: 13,    R_ELBOW: 14,
  L_WRIST: 15,    R_WRIST: 16,
  L_HIP: 23,      R_HIP: 24,
  L_KNEE: 25,     R_KNEE: 26,
  L_ANKLE: 27,    R_ANKLE: 28,
};

export function getPoint(lm, idx, width, height) {
  const p = lm[idx];
  if (!p || p.visibility < 0.5) return null;
  return { x: p.x * width, y: p.y * height, visibility: p.visibility };
}
