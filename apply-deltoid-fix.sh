#!/usr/bin/env bash
# =============================================================================
# MuscleMap — fix/deltoid-shoulder-angle
#
# Fix: deltoid activation pinned at 70-90% regardless of shoulder position.
# Root cause: 2D shoulder angle computed from hip->shoulder->elbow is unreliable
# when the camera is low (webcam) and/or hip landmark confidence is poor.
#
# Fix strategy:
#   - Measure shoulder flexion as the angle of the upper arm (shoulder->elbow)
#     from the vertical axis of the TORSO (shoulder->hip), projected in 2D.
#   - Use a larger denominator (90°) so small noise doesn't max out the signal.
#   - Ignore the sign of lateral deviation (we only care about forward lift).
#   - Shift the deltoid formula so "arm hanging" = ~15%, "arm raised 90°" = ~80%.
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — fix deltoid activation   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ Run this from inside the musclemap folder.${NC}"
  exit 1
fi

if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Uncommitted changes present. Commit or stash first.${NC}"
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo -e "${YELLOW}⚠ Switching to main first…${NC}"
  git checkout main
fi

echo -e "${GREEN}✓${NC} Ready to apply fix"
echo ""

# --- Branch ---
if git show-ref --verify --quiet refs/heads/fix/deltoid-shoulder-angle; then
  git branch -D fix/deltoid-shoulder-angle
fi
git checkout -b fix/deltoid-shoulder-angle

# --- Update bicep-curl.js: compute a proper torso-relative shoulder lift ---
echo -e "${BLUE}→ Updating src/exercises/bicep-curl.js…${NC}"
cat > src/exercises/bicep-curl.js <<'EOF'
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
EOF

# --- Update activation.js: rescale deltoid formula ---
echo -e "${BLUE}→ Updating src/biomechanics/activation.js…${NC}"
cat > src/biomechanics/activation.js <<'EOF'
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
EOF

# --- Update demo.js: pass through the new shoulderLift field for form check ---
echo -e "${BLUE}→ Updating src/sources/demo.js…${NC}"
python3 <<'PYEOF'
with open('src/sources/demo.js', 'r') as f:
    src = f.read()

# In the bicep curl branch of the demo, we currently generate a "shoulderR"
# angle. That's fed to the form check as shoulderAngle and from there the
# form rules look for shoulderFlex. Since we renamed the rule input to
# shoulderLift, we need to include both so the rules find it.

# Find the curl form-check block and add shoulderLift to the context objects.
old1 = '''    const formL = exercise.checkForm({
      elbowAngle: primaryL, kneeAngle: primaryL,
      shoulderAngle: secondaryL, hipAngle: secondaryL,
      phase: armL.currentPhase,
      atBottom: armL.currentPhase === 'up' && primaryL < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasL,
    });'''
new1 = '''    const formL = exercise.checkForm({
      elbowAngle: primaryL, kneeAngle: primaryL,
      shoulderAngle: secondaryL, hipAngle: secondaryL,
      shoulderLift: Math.max(0, 180 - secondaryL),
      phase: armL.currentPhase,
      atBottom: armL.currentPhase === 'up' && primaryL < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasL,
    });'''
src = src.replace(old1, new1)

old2 = '''    const formR = exercise.checkForm({
      elbowAngle: primaryR, kneeAngle: primaryR,
      shoulderAngle: secondaryR, hipAngle: secondaryR,
      phase: armR.currentPhase,
      atBottom: armR.currentPhase === 'up' && primaryR < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasR,
    });'''
new2 = '''    const formR = exercise.checkForm({
      elbowAngle: primaryR, kneeAngle: primaryR,
      shoulderAngle: secondaryR, hipAngle: secondaryR,
      shoulderLift: Math.max(0, 180 - secondaryR),
      phase: armR.currentPhase,
      atBottom: armR.currentPhase === 'up' && primaryR < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasR,
    });'''
src = src.replace(old2, new2)

with open('src/sources/demo.js', 'w') as f:
    f.write(src)
print('src/sources/demo.js updated')
PYEOF

# --- Commit ---
echo ""
echo -e "${BLUE}→ Committing changes…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit${NC}"
else
  git commit -q -m "fix: deltoid activation stuck near 80% during curls

Root cause: 2D shoulder angle computed from hip->shoulder->elbow becomes
unstable when those three points are nearly collinear (which is exactly
what happens during a bicep curl with elbows pinned to the torso).
Combined with noisy hip landmarks, this pushed the activation formula's
shoulder-flex input toward saturation.

Changes:
- Compute shoulder lift as angle between upper-arm vector and torso
  vector (stable because torso is long and well-tracked)
- Fall back to vertical reference when hip confidence is low
- Expand activation scaling: 90 deg denominator + 10 deg deadzone
- Lower resting deltoid from 0.20 to 0.15
- Add shoulderLift to form-rule context (replaces implicit shoulder math)
- Demo mode: pass shoulderLift through for rule consistency"
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Fix applied                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  Point the webcam at yourself, let your arms hang by your sides."
echo -e "  Deltoid should read ~15% (resting)."
echo -e "  Do a bicep curl with elbows pinned — deltoid should stay ~15-25%."
echo -e "  Now raise your arm forward (cheat the rep) — deltoid should climb."
echo ""
echo -e "${YELLOW}When satisfied, merge:${NC}"
echo -e "  ${BLUE}git push -u origin fix/deltoid-shoulder-angle${NC}"
echo -e "  ${BLUE}git checkout main && git merge fix/deltoid-shoulder-angle${NC}"
echo -e "  ${BLUE}git push && git branch -d fix/deltoid-shoulder-angle${NC}"
echo ""
echo -e "${YELLOW}If wrong, roll back:${NC}"
echo -e "  ${BLUE}git checkout main && git branch -D fix/deltoid-shoulder-angle${NC}"
echo ""
