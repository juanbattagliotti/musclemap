#!/usr/bin/env bash
# =============================================================================
# MuscleMap — feat/body-overlay
#
# Tier A body overlay: paint activation-colored shapes anchored to pose
# landmarks, drawn directly on the video feed. No segmentation, no 3D mesh.
#
# Usage:
#   cd musclemap
#   save this file as apply-body-overlay.sh in that folder
#   chmod +x apply-body-overlay.sh
#   git add apply-body-overlay.sh && git commit -m "chore: add overlay script"
#   ./apply-body-overlay.sh
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — Tier A body overlay      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ Run this from inside the musclemap folder.${NC}"; exit 1
fi
if [ ! -d ".git" ]; then
  echo -e "${RED}✗ No git repo found.${NC}"; exit 1
fi
if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Uncommitted changes. Commit or stash first.${NC}"; exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo -e "${YELLOW}⚠ Switching to main first…${NC}"
  git checkout main
fi

if git show-ref --verify --quiet refs/heads/feat/body-overlay; then
  git branch -D feat/body-overlay
fi
git checkout -b feat/body-overlay

# =============================================================================

echo -e "${BLUE}→ Writing src/ui/body-overlay.js…${NC}"
cat > src/ui/body-overlay.js <<'EOF'
// =========================================================================
// Tier A body overlay — paints activation-colored shapes directly on the
// video, anchored to pose landmarks. No segmentation; just geometric
// shapes that follow the body.
//
// Shapes are drawn per exercise in the painter object. Each painter:
//   - receives the landmarks, the canvas ctx, the canvas dimensions,
//     and per-side activation values
//   - draws shapes with alpha proportional to activation
//
// Keeping this as "soft paint" (blurred, semi-transparent) rather than
// hard colors because it reads better over real video.
// =========================================================================

const MUSCLE_COLORS = {
  // cool palette for left side
  biceps_L:     [0, 255, 157],
  deltoid_L:    [0, 200, 255],
  forearm_L:    [100, 255, 200],
  quads_L:      [0, 255, 157],
  glutes_L:     [0, 230, 180],
  hamstrings_L: [0, 180, 220],
  erectors_L:   [150, 220, 255],

  // warm palette for right side
  biceps_R:     [255, 180, 70],
  deltoid_R:    [255, 140, 100],
  forearm_R:    [255, 200, 130],
  quads_R:      [255, 180, 70],
  glutes_R:     [255, 160, 80],
  hamstrings_R: [255, 200, 120],
  erectors_R:   [255, 220, 180],
};

// Convert normalized pose landmarks (0..1) to pixel coordinates for the
// canvas. MediaPipe gives us x/y in [0, 1] — multiply by canvas size.
function px(lm, w, h) {
  return { x: lm.x * w, y: lm.y * h };
}

function alpha(activation) {
  // Keep a small resting baseline so the overlay is always faintly visible,
  // ramp to strong opacity at high activation. Nonlinear to make the
  // "someone's working hard" moment visually pop.
  const v = Math.max(0, Math.min(1, activation));
  return 0.12 + 0.55 * Math.pow(v, 1.4);
}

function fillStyle([r, g, b], activation) {
  return `rgba(${r}, ${g}, ${b}, ${alpha(activation)})`;
}

// Draw a rotated ellipse connecting two landmark points, with a given
// width (perpendicular thickness). This is the workhorse shape for limbs.
function drawLimbEllipse(ctx, p1, p2, widthPx, color, activation) {
  const dx = p2.x - p1.x;
  const dy = p2.y - p1.y;
  const length = Math.hypot(dx, dy);
  if (length < 2) return;

  const cx = (p1.x + p2.x) / 2;
  const cy = (p1.y + p2.y) / 2;
  const angle = Math.atan2(dy, dx);

  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(angle);

  // Soft outer glow (bigger, more transparent)
  ctx.fillStyle = fillStyle(color, activation * 0.5);
  ctx.beginPath();
  ctx.ellipse(0, 0, length / 2, widthPx * 0.75, 0, 0, 2 * Math.PI);
  ctx.fill();

  // Core (smaller, more opaque)
  ctx.fillStyle = fillStyle(color, activation);
  ctx.beginPath();
  ctx.ellipse(0, 0, length / 2.2, widthPx * 0.5, 0, 0, 2 * Math.PI);
  ctx.fill();

  ctx.restore();
}

// Draw a soft circle at a landmark. Used for deltoid / glutes.
function drawBlob(ctx, p, radiusPx, color, activation) {
  ctx.save();
  // Outer halo
  ctx.fillStyle = fillStyle(color, activation * 0.4);
  ctx.beginPath();
  ctx.arc(p.x, p.y, radiusPx * 1.2, 0, 2 * Math.PI);
  ctx.fill();
  // Core
  ctx.fillStyle = fillStyle(color, activation);
  ctx.beginPath();
  ctx.arc(p.x, p.y, radiusPx * 0.8, 0, 2 * Math.PI);
  ctx.fill();
  ctx.restore();
}

// Estimate limb thickness from the distance between the two shoulder
// landmarks as a proxy for body size in the frame. This keeps the overlay
// visually proportional whether the subject is near or far.
function bodyScale(landmarks, w) {
  const lS = landmarks[11], rS = landmarks[12];
  if (!lS || !rS) return w * 0.04;
  const dx = (lS.x - rS.x) * w;
  const dy = (lS.y - rS.y) * w;  // use w on both so the scale isn't squashed
  return Math.max(20, Math.hypot(dx, dy) * 0.35);
}

// =========================================================================
// BICEP CURL painter
// =========================================================================
function paintBicepCurl(ctx, landmarks, w, h, actsL, actsR) {
  if (!landmarks || landmarks.length < 17) return;
  const limbW = bodyScale(landmarks, w) * 0.45;

  // LEFT side (subject's left = camera right when mirrored)
  const lShoulder = px(landmarks[11], w, h);
  const lElbow = px(landmarks[13], w, h);
  const lWrist = px(landmarks[15], w, h);

  if (landmarks[11].visibility > 0.5 && landmarks[13].visibility > 0.5) {
    drawLimbEllipse(ctx, lShoulder, lElbow, limbW, MUSCLE_COLORS.biceps_L, actsL.bicep || 0);
    drawBlob(ctx, lShoulder, limbW * 1.1, MUSCLE_COLORS.deltoid_L, actsL.deltoid || 0);
  }
  if (landmarks[13].visibility > 0.5 && landmarks[15].visibility > 0.5) {
    drawLimbEllipse(ctx, lElbow, lWrist, limbW * 0.85, MUSCLE_COLORS.forearm_L, actsL.forearm || 0);
  }

  // RIGHT side
  const rShoulder = px(landmarks[12], w, h);
  const rElbow = px(landmarks[14], w, h);
  const rWrist = px(landmarks[16], w, h);

  if (landmarks[12].visibility > 0.5 && landmarks[14].visibility > 0.5) {
    drawLimbEllipse(ctx, rShoulder, rElbow, limbW, MUSCLE_COLORS.biceps_R, actsR.bicep || 0);
    drawBlob(ctx, rShoulder, limbW * 1.1, MUSCLE_COLORS.deltoid_R, actsR.deltoid || 0);
  }
  if (landmarks[14].visibility > 0.5 && landmarks[16].visibility > 0.5) {
    drawLimbEllipse(ctx, rElbow, rWrist, limbW * 0.85, MUSCLE_COLORS.forearm_R, actsR.forearm || 0);
  }
}

// =========================================================================
// SQUAT painter
// =========================================================================
function paintSquat(ctx, landmarks, w, h, actsL, actsR) {
  if (!landmarks || landmarks.length < 29) return;
  const limbW = bodyScale(landmarks, w) * 0.55;

  // LEFT leg
  const lHip = px(landmarks[23], w, h);
  const lKnee = px(landmarks[25], w, h);
  const lAnkle = px(landmarks[27], w, h);

  if (landmarks[23].visibility > 0.4 && landmarks[25].visibility > 0.4) {
    // Front of thigh = quads
    drawLimbEllipse(ctx, lHip, lKnee, limbW, MUSCLE_COLORS.quads_L, actsL.quads || 0);
    // Glute blob at the hip landmark
    drawBlob(ctx, lHip, limbW * 0.9, MUSCLE_COLORS.glutes_L, actsL.glutes || 0);
  }
  if (landmarks[25].visibility > 0.4 && landmarks[27].visibility > 0.4) {
    // Hamstring shown as a thinner ellipse along the lower part of the thigh;
    // since we only have 2D, we overlay it slightly offset from quads
    drawLimbEllipse(ctx, lHip, lKnee, limbW * 0.6, MUSCLE_COLORS.hamstrings_L, actsL.hamstrings || 0);
  }

  // RIGHT leg
  const rHip = px(landmarks[24], w, h);
  const rKnee = px(landmarks[26], w, h);
  const rAnkle = px(landmarks[28], w, h);

  if (landmarks[24].visibility > 0.4 && landmarks[26].visibility > 0.4) {
    drawLimbEllipse(ctx, rHip, rKnee, limbW, MUSCLE_COLORS.quads_R, actsR.quads || 0);
    drawBlob(ctx, rHip, limbW * 0.9, MUSCLE_COLORS.glutes_R, actsR.glutes || 0);
  }
  if (landmarks[26].visibility > 0.4 && landmarks[28].visibility > 0.4) {
    drawLimbEllipse(ctx, rHip, rKnee, limbW * 0.6, MUSCLE_COLORS.hamstrings_R, actsR.hamstrings || 0);
  }

  // ERECTORS — draw along the spine (midShoulder to midHip)
  const lShoulder = px(landmarks[11], w, h);
  const rShoulder = px(landmarks[12], w, h);
  const midShoulder = { x: (lShoulder.x + rShoulder.x) / 2, y: (lShoulder.y + rShoulder.y) / 2 };
  const midHip = { x: (lHip.x + rHip.x) / 2, y: (lHip.y + rHip.y) / 2 };

  if (landmarks[11].visibility > 0.4 && landmarks[12].visibility > 0.4 &&
      landmarks[23].visibility > 0.4 && landmarks[24].visibility > 0.4) {
    // Use the average of L/R erector activation (they're bilateral)
    const erectorAct = ((actsL.erectors || 0) + (actsR.erectors || 0)) / 2;
    // Paint with left-side cool color on the spine
    drawLimbEllipse(ctx, midShoulder, midHip, limbW * 0.7, MUSCLE_COLORS.erectors_L, erectorAct);
  }
}

// =========================================================================
// Registry
// =========================================================================
const PAINTERS = {
  bicepCurl: paintBicepCurl,
  squat: paintSquat,
};

export function paintBodyOverlay(ctx, exerciseId, landmarks, canvasW, canvasH, actsL, actsR, enabled = true) {
  if (!enabled) return;
  const painter = PAINTERS[exerciseId];
  if (!painter) return;

  // Use additive-style blending so overlays layer well over the video
  ctx.save();
  ctx.globalCompositeOperation = 'screen';
  painter(ctx, landmarks, canvasW, canvasH, actsL, actsR);
  ctx.restore();
}
EOF

echo -e "${BLUE}→ Updating src/main.js (wire the overlay into the predict loop)…${NC}"
python3 <<'PYEOF'
with open('src/main.js', 'r') as f:
    src = f.read()

# 1. Add import
if 'paintBodyOverlay' not in src:
    src = src.replace(
        "import { runDemo, stopDemo } from './sources/demo.js';",
        "import { runDemo, stopDemo } from './sources/demo.js';\n"
        "import { paintBodyOverlay } from './ui/body-overlay.js';"
    )

# 2. Add an overlay-enabled state variable near the other state at the top
if 'overlayEnabled' not in src:
    src = src.replace(
        "let setActive = false;",
        "let setActive = false;\n"
        "let overlayEnabled = true;"
    )

# 3. Add a click listener in init() for the overlay toggle button
if 'onToggleOverlay' not in src:
    src = src.replace(
        "if (dom.endSetBtn) dom.endSetBtn.addEventListener('click', onEndSet);",
        "if (dom.endSetBtn) dom.endSetBtn.addEventListener('click', onEndSet);\n"
        "  if (dom.overlayToggle) dom.overlayToggle.addEventListener('click', onToggleOverlay);"
    )

# 4. Add the overlay call inside predictLoop, right after drawLandmarksAndConnectors
#    but before the angle-arc drawing, so arcs sit on top of the muscle paint.
old_paint_anchor = "drawLandmarksAndConnectors(drawingUtils, poseUtils.PoseLandmarker, lm);"
new_paint_anchor = """drawLandmarksAndConnectors(drawingUtils, poseUtils.PoseLandmarker, lm);

        // Body overlay — paint activation-colored muscle shapes over the video
        // Computed once we have both sides' activations (see below)"""

if new_paint_anchor not in src:
    src = src.replace(old_paint_anchor, new_paint_anchor)

# 5. Insert the actual paint call after the two processSide calls. Find
#    the block that renders muscle lists and insert paintBodyOverlay just
#    before renderMuscleList.
old_render_block = """        renderMuscleList(dom.muscleListLEl, resultL.activations, false);
        renderMuscleList(dom.muscleListREl, resultR.activations, true);"""
new_render_block = """        // Paint the body overlay first so that UI chrome (angle arcs, etc)
        // draws on top of it
        paintBodyOverlay(dom.ctx, currentExercise.id, lm, dom.overlay.width, dom.overlay.height,
                         resultL.activations, resultR.activations, overlayEnabled);

        renderMuscleList(dom.muscleListLEl, resultL.activations, false);
        renderMuscleList(dom.muscleListREl, resultR.activations, true);"""

if 'paintBodyOverlay(dom.ctx' not in src:
    src = src.replace(old_render_block, new_render_block)

# 6. Add onToggleOverlay handler near the other handlers (right before init())
if 'function onToggleOverlay' not in src:
    handler = '''
function onToggleOverlay() {
  overlayEnabled = !overlayEnabled;
  if (dom.overlayToggle) {
    dom.overlayToggle.textContent = overlayEnabled ? 'Overlay: ON' : 'Overlay: OFF';
    dom.overlayToggle.classList.toggle('active', overlayEnabled);
  }
  log('body overlay ' + (overlayEnabled ? 'enabled' : 'disabled'), 'ok');
}

'''
    src = src.replace('init();', handler + 'init();')

with open('src/main.js', 'w') as f:
    f.write(src)
print('src/main.js updated')
PYEOF

echo -e "${BLUE}→ Updating src/ui/dom.js…${NC}"
python3 <<'PYEOF'
with open('src/ui/dom.js', 'r') as f:
    src = f.read()

if 'overlayToggle' not in src:
    src = src.replace(
        "endSetBtn: $('endSetBtn'),",
        "endSetBtn: $('endSetBtn'),\n"
        "  overlayToggle: $('overlayToggle'),"
    )

with open('src/ui/dom.js', 'w') as f:
    f.write(src)
print('src/ui/dom.js updated')
PYEOF

echo -e "${BLUE}→ Updating index.html (overlay toggle button)…${NC}"
python3 <<'PYEOF'
import re
with open('index.html', 'r') as f:
    html = f.read()

html = re.sub(
    r'<span class="tag">MUSCLEMAP · v0\.[0-9]+[^<]*</span>',
    '<span class="tag">MUSCLEMAP · v0.7 · BODY OVERLAY</span>',
    html
)

# Add the overlay toggle button next to End set
if 'id="overlayToggle"' not in html:
    html = html.replace(
        '<button id="endSetBtn" class="danger" style="display:none;">End set</button>',
        '<button id="endSetBtn" class="danger" style="display:none;">End set</button>\n'
        '          <button id="overlayToggle" class="secondary active">Overlay: ON</button>'
    )

with open('index.html', 'w') as f:
    f.write(html)
print('index.html updated')
PYEOF

echo -e "${BLUE}→ Appending overlay-toggle styles…${NC}"
if ! grep -q "overlayToggle" src/ui/styles.css; then
  cat >> src/ui/styles.css <<'EOF'

/* --- Overlay toggle button --- */
button.secondary.active {
  background: rgba(0,255,157,0.08);
  border-color: var(--accent);
  color: var(--accent);
}
button.secondary.active:hover:not(:disabled) {
  background: rgba(0,255,157,0.12);
}
EOF
  echo -e "${GREEN}  ✓${NC} styles appended"
fi

# --- Commit ---
echo ""
echo -e "${BLUE}→ Committing…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit${NC}"
else
  git commit -q -m "feat: Tier A body overlay — paint muscles on the video

- New module src/ui/body-overlay.js: draws activation-colored shapes
  anchored to pose landmarks, rendered over the video feed
- Painter per exercise (bicep curl + squat), both handle bilateral
- Soft-paint style: halo + core with nonlinear alpha ramp, 'screen'
  blend so colors layer well on real video
- Limb thickness scales with body size in frame (shoulder distance)
- Toggle button to turn the overlay on/off during demos
- Rendering order: pose skeleton -> muscle overlay -> angle arcs, so
  chrome reads cleanly on top of the paint

This is Tier A of the Tier A/B/C progression discussed in architecture
docs. Intentionally avoids body segmentation (Tier B) and 3D mesh
fitting (Tier C) to stay fast and robust on a laptop webcam."
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Body overlay ready               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  1. Click ${BLUE}Demo${NC} — you'll see colored shapes painted on the body"
echo -e "  2. Try ${BLUE}Webcam${NC} too — works with real video"
echo -e "  3. Switch ${BLUE}Exercise${NC} to Squat — legs/spine light up instead"
echo -e "  4. Click ${BLUE}Overlay: ON${NC} to toggle the feature off and compare"
echo ""
echo -e "${YELLOW}Merge when ready:${NC}"
echo -e "  ${BLUE}git push -u origin feat/body-overlay${NC}"
echo -e "  ${BLUE}git checkout main && git merge feat/body-overlay${NC}"
echo -e "  ${BLUE}git push && git branch -d feat/body-overlay${NC}"
echo ""
