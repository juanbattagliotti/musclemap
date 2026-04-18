#!/usr/bin/env bash
# =============================================================================
# MuscleMap — apply feat/squat-exercise branch
#
# Run this from inside your musclemap/ folder. It will:
#   1. Create a new git branch 'feat/squat-exercise'
#   2. Create/overwrite every file the feature needs
#   3. Commit the changes
#
# You still do the final merge to main yourself (instructions printed at end).
#
# Usage:
#   cd musclemap            (be INSIDE the project folder first)
#   save this file as apply-squat.sh in that folder
#   chmod +x apply-squat.sh
#   ./apply-squat.sh
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — apply squat feature      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# --- Preflight ---
if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ This doesn't look like your musclemap folder.${NC}"
  echo "  Make sure you're inside the project folder before running this script."
  echo "  Try: cd musclemap"
  exit 1
fi

if [ ! -d ".git" ]; then
  echo -e "${RED}✗ No git repo found here.${NC}"
  echo "  Did you run setup.sh first?"
  exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ You have uncommitted changes.${NC}"
  echo "  Commit or stash them first:"
  echo "    git add . && git commit -m 'wip'"
  echo "  Or stash:"
  echo "    git stash"
  exit 1
fi

echo -e "${GREEN}✓${NC} Inside musclemap repo, tree is clean"
echo ""

# --- Create feature branch ---
echo -e "${BLUE}→ Creating feature branch…${NC}"
if git show-ref --verify --quiet refs/heads/feat/squat-exercise; then
  echo -e "${YELLOW}⚠${NC} Branch 'feat/squat-exercise' already exists. Switching to it."
  git checkout feat/squat-exercise
else
  git checkout -b feat/squat-exercise
fi

# =============================================================================
# WRITE FILES
# =============================================================================

echo -e "${BLUE}→ Writing src/biomechanics/activation.js…${NC}"
cat > src/biomechanics/activation.js <<'EOF'
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
EOF

echo -e "${BLUE}→ Writing src/exercises/squat.js…${NC}"
cat > src/exercises/squat.js <<'EOF'
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
EOF

echo -e "${BLUE}→ Writing src/exercises/index.js…${NC}"
cat > src/exercises/index.js <<'EOF'
import { bicepCurl } from './bicep-curl.js';
import { squat } from './squat.js';

const registry = {
  bicepCurl,
  squat,
};

export function getExercise(id) {
  const ex = registry[id];
  if (!ex) throw new Error('Unknown exercise: ' + id);
  return ex;
}

export function listExercises() {
  return Object.keys(registry).map(id => ({ id, name: registry[id].name }));
}
EOF

echo -e "${BLUE}→ Writing src/analytics/rep-detector.js…${NC}"
cat > src/analytics/rep-detector.js <<'EOF'
const RANK = { good: 0, warning: 1, bad: 2 };

export function detectRep(state, angle, primaryAct, formCheck, thresholds) {
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
    startNewRep(state, angle);
  } else if (state.currentPhase === 'down' && angle < FLEX_THR) {
    state.currentPhase = 'up';
  } else if (state.currentPhase === 'up' && angle > EXT_THR) {
    state.repCount++;
    state.repPeaks.push(state.peakBicepThisRep);
    state.repROMs.push([state.minAngleThisRep, state.maxAngleThisRep]);
    state.repFormFlags.push(state.worstFormThisRep);
    state.currentPhase = 'down';
    startNewRep(state, angle);
    return true;
  }
  return false;
}

function startNewRep(state, angle) {
  state.minAngleThisRep = angle;
  state.maxAngleThisRep = angle;
  state.peakBicepThisRep = 0;
  state.worstFormThisRep = 'good';
}

export function isAtBottom(state, angle, thresholds) {
  const FLEX_THR = thresholds?.flex ?? 80;
  return state.currentPhase === 'up' && angle < FLEX_THR + 15;
}
EOF

echo -e "${BLUE}→ Writing src/main.js…${NC}"
cat > src/main.js <<'EOF'
import { loadPoseLandmarker } from './pose/loader.js';
import { dom, log } from './ui/dom.js';
import { renderMuscleList, updateBodyDiagram, setStatus, setPoseStatus,
         updateRepUI, updateAsymmetryUI, updateFormBanner, clearOverlay,
         showSource, hideSource, drawLandmarksAndConnectors, drawAngleArc,
         setMuscleLabels, setExerciseTitle } from './ui/render.js';
import { makeArmState, resetArmState } from './analytics/session-state.js';
import { detectRep, isAtBottom } from './analytics/rep-detector.js';
import { computeAsymmetry } from './analytics/asymmetry.js';
import { getExercise, listExercises } from './exercises/index.js';
import { startWebcam, stopWebcam } from './sources/webcam.js';
import { startUploadedVideo } from './sources/video-upload.js';
import { runDemo, stopDemo } from './sources/demo.js';

let poseLandmarker = null;
let poseUtils = null;
let drawingUtils = null;
let mode = null;
let running = false;
let lastVideoTime = -1;
let currentStream = null;
let videoUrl = null;

let currentExercise = getExercise('bicepCurl');
const armL = makeArmState();
const armR = makeArmState();

const MUSCLE_SETS = {
  bicepCurl: [
    { key: 'bicep', label: 'Biceps brachii' },
    { key: 'deltoid', label: 'Ant. deltoid' },
    { key: 'forearm', label: 'Forearm flex.' }
  ],
  squat: [
    { key: 'quads', label: 'Quadriceps' },
    { key: 'glutes', label: 'Glutes' },
    { key: 'hamstrings', label: 'Hamstrings' },
    { key: 'erectors', label: 'Erectors' }
  ]
};

async function init() {
  log('prototype v0.4 ready — squat + form feedback');

  dom.startBtn.addEventListener('click', onStartWebcam);
  dom.videoFileInput.addEventListener('change', onVideoFile);
  dom.resetBtn.addEventListener('click', onReset);
  dom.demoBtn.addEventListener('click', onDemo);
  dom.stopBtn.addEventListener('click', onStop);

  if (dom.exerciseSelect) {
    listExercises().forEach(ex => {
      const opt = document.createElement('option');
      opt.value = ex.id;
      opt.textContent = ex.name;
      dom.exerciseSelect.appendChild(opt);
    });
    dom.exerciseSelect.addEventListener('change', (e) => {
      selectExercise(e.target.value);
    });
  }

  selectExercise('bicepCurl');

  try {
    const loaded = await loadPoseLandmarker((phase) => setPoseStatus(phase));
    poseLandmarker = loaded.landmarker;
    poseUtils = loaded.utils;
    drawingUtils = new poseUtils.DrawingUtils(dom.ctx);
    setPoseStatus('ready');
    log('pose model ready', 'ok');
  } catch (e) {
    setPoseStatus('failed');
    log('pose load failed: ' + (e.message || e), 'err');
  }
}

function selectExercise(id) {
  currentExercise = getExercise(id);
  onReset();
  setExerciseTitle(currentExercise.name);
  setMuscleLabels(MUSCLE_SETS[id]);
  log('exercise: ' + currentExercise.name, 'ok');
}

function emptyActivations() {
  const obj = {};
  (MUSCLE_SETS[currentExercise.id] || []).forEach(m => obj[m.key] = 0);
  return obj;
}

async function onStartWebcam() {
  if (running) return;
  try {
    setStatus('REQUESTING CAMERA…', 'loading');
    const result = await startWebcam(dom.video);
    currentStream = result.stream;
    mode = 'webcam';
    running = true;
    showSource('LIVE WEBCAM');
    dom.stopBtn.style.display = 'inline-block';
    dom.startBtn.disabled = true;
    setStatus(poseLandmarker ? 'TRACKING' : 'CAMERA ON — POSE LOADING', '');
    log('camera acquired', 'ok');
    predictLoop();
  } catch (e) {
    const name = e.name || 'Error';
    let msg = 'CAMERA BLOCKED';
    if (name === 'NotAllowedError') msg = 'PERMISSION DENIED';
    else if (name === 'NotFoundError') msg = 'NO CAMERA FOUND';
    else if (name === 'NotReadableError') msg = 'CAMERA IN USE';
    setStatus(msg, 'error');
    log(name + ': ' + (e.message || 'failed'), 'err');
  }
}

async function onVideoFile(e) {
  const file = e.target.files && e.target.files[0];
  if (!file) return;
  if (running) onStop();

  log('loading video: ' + file.name);
  if (videoUrl) URL.revokeObjectURL(videoUrl);
  videoUrl = URL.createObjectURL(file);
  try {
    await startUploadedVideo(dom.video, videoUrl, () => {
      log('video analysis complete', 'ok');
      running = false;
      setStatus('ANALYSIS COMPLETE', '');
    });
    mode = 'video';
    running = true;
    showSource('UPLOADED VIDEO');
    dom.progressBar.style.display = 'block';
    dom.stopBtn.style.display = 'inline-block';
    dom.startBtn.disabled = true;
    setStatus(poseLandmarker ? 'ANALYZING' : 'POSE LOADING', '');
    predictLoop();
  } catch (err) {
    log('video load failed: ' + err.message, 'err');
  }
}

function onReset() {
  resetArmState(armL);
  resetArmState(armR);
  const empty = emptyActivations();
  renderMuscleList(dom.muscleListLEl, empty, false);
  renderMuscleList(dom.muscleListREl, empty, true);
  updateBodyDiagram(empty, empty);
  dom.angleLEl.textContent = '—°';
  dom.angleREl.textContent = '—°';
  dom.romLEl.textContent = '—';
  dom.romREl.textContent = '—';
  dom.repHistoryEl.innerHTML = '';
  updateAsymmetryUI({ signed: 0, abs: 0, verdict: null });
  updateFormBanner(null);
  updateRepUI(armL, armR);
}

function onDemo() {
  if (running) onStop();
  mode = 'demo';
  running = true;
  showSource('DEMO MODE');
  dom.stopBtn.style.display = 'inline-block';
  setStatus('SIMULATED ' + currentExercise.name.toUpperCase(), '');
  log('demo — ' + currentExercise.name + ' simulation', 'ok');

  runDemo(currentExercise, armL, armR, {
    onFrame: (actsL, actsR, primaryAngleL, primaryAngleR, formL, formR) => {
      dom.angleLEl.textContent = Math.round(primaryAngleL) + '°';
      dom.angleREl.textContent = Math.round(primaryAngleR) + '°';
      renderMuscleList(dom.muscleListLEl, actsL, false);
      renderMuscleList(dom.muscleListREl, actsR, true);
      updateBodyDiagram(actsL, actsR);
      updateRepUI(armL, armR);
      updateAsymmetryUI(computeAsymmetry(armL, armR));
      updateFormBanner(mergeFormVerdicts(formL, formR));
    },
    isRunning: () => running && mode === 'demo'
  });
}

function onStop() {
  running = false;
  if (currentStream) { stopWebcam(currentStream); currentStream = null; }
  if (videoUrl) { URL.revokeObjectURL(videoUrl); videoUrl = null; }
  if (mode === 'demo') stopDemo();

  dom.video.pause();
  dom.video.srcObject = null;
  dom.video.src = '';
  dom.video.classList.remove('mirrored');
  dom.overlay.classList.remove('mirrored');
  clearOverlay();
  hideSource();
  dom.progressBar.style.display = 'none';
  dom.stopBtn.style.display = 'none';
  dom.startBtn.disabled = false;
  updateFormBanner(null);
  setStatus('SELECT INPUT SOURCE', 'loading');
  mode = null;
}

function predictLoop() {
  if (!running) return;

  if (poseLandmarker && dom.video.currentTime !== lastVideoTime && dom.video.readyState >= 2) {
    lastVideoTime = dom.video.currentTime;
    const now = performance.now();

    try {
      const result = poseLandmarker.detectForVideo(dom.video, now);
      clearOverlay();

      if (result.landmarks && result.landmarks.length > 0) {
        const lm = result.landmarks[0];
        drawLandmarksAndConnectors(drawingUtils, poseUtils.PoseLandmarker, lm);

        const resultL = processSide(lm, currentExercise, armL, 'left', now);
        const resultR = processSide(lm, currentExercise, armR, 'right', now);

        if (resultL.primaryAngle !== null) {
          dom.angleLEl.textContent = Math.round(resultL.primaryAngle) + '°';
          if (resultL.arcPoint) drawAngleArc(resultL.arcPoint, resultL.primaryAngle, resultL.formCheck?.color || '#00ff9d');
        }
        if (resultR.primaryAngle !== null) {
          dom.angleREl.textContent = Math.round(resultR.primaryAngle) + '°';
          if (resultR.arcPoint) drawAngleArc(resultR.arcPoint, resultR.primaryAngle, resultR.formCheck?.color || '#ffd166');
        }

        renderMuscleList(dom.muscleListLEl, resultL.activations, false);
        renderMuscleList(dom.muscleListREl, resultR.activations, true);
        updateBodyDiagram(resultL.activations, resultR.activations);
        updateRepUI(armL, armR);
        updateAsymmetryUI(computeAsymmetry(armL, armR));
        updateFormBanner(mergeFormVerdicts(resultL.formCheck, resultR.formCheck));
      }
    } catch (e) {
      log('inference error: ' + e.message, 'err');
    }
  }

  if (mode === 'video' && dom.video.duration > 0) {
    dom.progressFill.style.width = (dom.video.currentTime / dom.video.duration * 100) + '%';
  }

  requestAnimationFrame(predictLoop);
}

function processSide(landmarks, exercise, armState, side, timestamp) {
  const keypoints = exercise.getKeypoints(landmarks, side);
  if (!keypoints) {
    return { activations: emptyActivations(), formCheck: null, primaryAngle: null, arcPoint: null };
  }

  const angles = exercise.computeAngles(keypoints);
  const primaryAngle = angles.elbowAngle;
  const secondaryAngle = angles.shoulderAngle;

  const angVel = computeAngVel(armState, primaryAngle, timestamp);

  let activations;
  if (exercise.estimateActivationsFull) {
    activations = exercise.estimateActivationsFull(primaryAngle, secondaryAngle, angles.trunkLean || 0, angVel);
  } else {
    activations = exercise.estimateActivations(primaryAngle, secondaryAngle, angVel);
  }

  const ctx = {
    ...angles,
    phase: armState.currentPhase,
    atBottom: isAtBottom(armState, primaryAngle, exercise.repThresholds),
  };
  const formCheck = exercise.checkForm(ctx);

  const primaryMuscleKey = (MUSCLE_SETS[exercise.id] || [])[0]?.key || 'quads';
  const primaryAct = activations[primaryMuscleKey] || 0;
  detectRep(armState, primaryAngle, primaryAct, formCheck, exercise.repThresholds);

  const arcPoint = keypoints.elbow || keypoints.knee;
  return { activations, formCheck, primaryAngle, arcPoint };
}

function computeAngVel(state, angle, timestamp) {
  state.angleHistory.push(angle);
  state.angleTimestamps.push(timestamp);
  if (state.angleHistory.length > 10) {
    state.angleHistory.shift();
    state.angleTimestamps.shift();
  }
  if (state.angleHistory.length < 2) return 0;
  const dt = (state.angleTimestamps.at(-1) - state.angleTimestamps[0]) / 1000;
  if (dt <= 0) return 0;
  return (state.angleHistory.at(-1) - state.angleHistory[0]) / dt;
}

function mergeFormVerdicts(formL, formR) {
  if (!formL && !formR) return null;
  const order = { bad: 3, warning: 2, good: 1 };
  const worst = [formL, formR].filter(Boolean)
    .sort((a, b) => order[b.verdict] - order[a.verdict])[0];
  return worst;
}

init();
EOF

echo -e "${BLUE}→ Writing src/ui/dom.js…${NC}"
cat > src/ui/dom.js <<'EOF'
const $ = (id) => document.getElementById(id);

export const dom = {
  video: $('video'),
  overlay: $('overlay'),
  ctx: $('overlay').getContext('2d'),

  statusEl: $('status'),
  poseStatusEl: $('poseStatus'),
  sourceBadge: $('sourceBadge'),
  formBanner: $('formBanner'),
  formVerdictEl: $('formVerdict'),
  formCueEl: $('formCue'),

  startBtn: $('startBtn'),
  videoFileInput: $('videoFile'),
  resetBtn: $('resetBtn'),
  demoBtn: $('demoBtn'),
  stopBtn: $('stopBtn'),
  progressBar: $('progressBar'),
  progressFill: $('progressFill'),
  logEl: $('log'),

  exerciseSelect: $('exerciseSelect'),

  repCountLEl: $('repCountL'),
  repCountREl: $('repCountR'),
  goodFormRepsEl: $('goodFormReps'),
  romLEl: $('romL'),
  romREl: $('romR'),
  repHistoryEl: $('repHistory'),

  angleLEl: $('angleL'),
  angleREl: $('angleR'),
  muscleListLEl: $('muscleListL'),
  muscleListREl: $('muscleListR'),

  asymIndicator: $('asymIndicator'),
  asymVerdict: $('asymVerdict'),
};

export function log(msg, cls) {
  const line = document.createElement('div');
  if (cls) line.className = cls;
  line.textContent = '> ' + msg;
  dom.logEl.appendChild(line);
  dom.logEl.scrollTop = dom.logEl.scrollHeight;
}
EOF

echo -e "${BLUE}→ Writing src/ui/render.js…${NC}"
cat > src/ui/render.js <<'EOF'
import { dom } from './dom.js';

let currentMuscleMeta = [
  { key: 'bicep', label: 'Biceps brachii' },
  { key: 'deltoid', label: 'Ant. deltoid' },
  { key: 'forearm', label: 'Forearm flex.' }
];

export function setMuscleLabels(muscleMeta) {
  currentMuscleMeta = muscleMeta;
}

export function setExerciseTitle(name) {
  const el = document.getElementById('exerciseTitle');
  if (el) el.textContent = name + ' analyzer';
}

export function setStatus(text, cls) {
  dom.statusEl.textContent = text;
  dom.statusEl.className = 'status ' + (cls || '');
}

export function setPoseStatus(phase) {
  const map = {
    loading: ['POSE: LOADING…', 'loading'],
    wasm: ['POSE: LOADING WASM…', 'loading'],
    model: ['POSE: LOADING MODEL…', 'loading'],
    ready: ['POSE: READY', 'ready'],
    failed: ['POSE: UNAVAILABLE', 'failed'],
  };
  const [text, cls] = map[phase] || map.loading;
  dom.poseStatusEl.textContent = text;
  dom.poseStatusEl.className = 'pose-status ' + cls;
}

export function showSource(label) {
  dom.sourceBadge.textContent = label;
  dom.sourceBadge.style.display = 'block';
}
export function hideSource() {
  dom.sourceBadge.style.display = 'none';
}

export function clearOverlay() {
  dom.ctx.clearRect(0, 0, dom.overlay.width, dom.overlay.height);
}

export function renderMuscleList(containerEl, acts, isRight) {
  containerEl.innerHTML = '';
  currentMuscleMeta.forEach(m => {
    const v = acts[m.key] || 0;
    const row = document.createElement('div');
    row.className = 'muscle-row';
    row.innerHTML =
      '<span class="muscle-name">' + m.label + '</span>' +
      '<div class="muscle-bar"><div class="muscle-fill ' + (isRight ? 'right' : '') + '" style="width:' + (v*100) + '%"></div></div>' +
      '<span class="muscle-pct">' + Math.round(v*100) + '%</span>';
    containerEl.appendChild(row);
  });
}

function colorForActivation(v, warm) {
  if (warm) {
    const r = Math.round(42 + v * (255 - 42));
    const g = Math.round(47 + v * (209 - 47));
    const b = Math.round(58 + v * (102 - 58));
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }
  const r = Math.round(42 + v * (0 - 42));
  const g = Math.round(47 + v * (255 - 47));
  const b = Math.round(58 + v * (157 - 58));
  return 'rgb(' + r + ',' + g + ',' + b + ')';
}

export function updateBodyDiagram(actsL, actsR) {
  const set = (id, v, warm) => {
    const el = document.getElementById(id);
    if (el) el.setAttribute('fill', colorForActivation(v, warm));
  };
  set('muscle-ldelt', actsL.deltoid || 0, false);
  set('muscle-lbicep', actsL.bicep || 0, false);
  set('muscle-lforearm', actsL.forearm || 0, false);
  set('muscle-rdelt', actsR.deltoid || 0, true);
  set('muscle-rbicep', actsR.bicep || 0, true);
  set('muscle-rforearm', actsR.forearm || 0, true);
}

export function updateRepUI(armL, armR) {
  dom.repCountLEl.textContent = armL.repCount;
  dom.repCountREl.textContent = armR.repCount;

  const goodL = armL.repFormFlags.filter(f => f === 'good').length;
  const goodR = armR.repFormFlags.filter(f => f === 'good').length;
  dom.goodFormRepsEl.textContent =
    goodL + '/' + armL.repCount + ' · ' + goodR + '/' + armR.repCount;

  if (armL.repROMs.length) {
    const [mn, mx] = armL.repROMs[armL.repROMs.length - 1];
    dom.romLEl.textContent = Math.round(mn) + '–' + Math.round(mx);
  }
  if (armR.repROMs.length) {
    const [mn, mx] = armR.repROMs[armR.repROMs.length - 1];
    dom.romREl.textContent = Math.round(mn) + '–' + Math.round(mx);
  }

  const maxReps = Math.max(armL.repPeaks.length, armR.repPeaks.length);
  const recent = Math.min(maxReps, 8);
  dom.repHistoryEl.innerHTML = '';
  for (let i = maxReps - recent; i < maxReps; i++) {
    if (i >= 0 && i < armL.repPeaks.length) {
      dom.repHistoryEl.appendChild(makeRepBar(armL.repPeaks[i], armL.repFormFlags[i], 'cool', i === armL.repPeaks.length - 1));
    }
    if (i >= 0 && i < armR.repPeaks.length) {
      dom.repHistoryEl.appendChild(makeRepBar(armR.repPeaks[i], armR.repFormFlags[i], 'warm', i === armR.repPeaks.length - 1));
    }
  }
}

function makeRepBar(peak, formFlag, palette, isLatest) {
  const bar = document.createElement('div');
  bar.className = 'rep-bar' + (isLatest ? ' latest' : '');
  bar.style.height = Math.max(4, peak * 45) + 'px';
  const colors = {
    good:    palette === 'cool' ? '#00ff9d' : '#ffd166',
    warning: '#ffb347',
    bad:     '#ff6b6b'
  };
  bar.style.background = colors[formFlag] || colors.good;
  return bar;
}

export function updateAsymmetryUI({ signed, abs, verdict }) {
  if (!verdict) {
    dom.asymVerdict.textContent = 'AWAITING REPS';
    dom.asymVerdict.style.color = 'var(--text-dim)';
    dom.asymIndicator.style.left = '50%';
    return;
  }
  const pct = Math.max(5, Math.min(95, 50 + (signed / 0.3) * 40));
  dom.asymIndicator.style.left = pct + '%';
  const colors = { balanced: 'var(--accent)', mild: 'var(--amber)', notable: 'var(--warn)' };
  dom.asymVerdict.textContent = verdict.label;
  dom.asymVerdict.style.color = colors[verdict.severity];
}

export function updateFormBanner(formCheck) {
  if (!formCheck) {
    dom.formBanner.style.display = 'none';
    return;
  }
  dom.formBanner.style.display = 'block';
  dom.formBanner.className = 'form-banner ' + formCheck.verdict;
  dom.formVerdictEl.textContent = formCheck.verdictLabel;
  dom.formCueEl.textContent = formCheck.cue || '';
}

export function drawLandmarksAndConnectors(drawingUtils, PoseLandmarker, landmarks) {
  drawingUtils.drawConnectors(landmarks, PoseLandmarker.POSE_CONNECTIONS, {
    color: 'rgba(0,255,157,0.5)', lineWidth: 2
  });
  drawingUtils.drawLandmarks(landmarks, {
    color: '#00ff9d', fillColor: '#00ff9d', radius: 3
  });
}

export function drawAngleArc(elbowPoint, angle, color) {
  const scaledX = elbowPoint.x * dom.overlay.width;
  const scaledY = elbowPoint.y * dom.overlay.height;
  dom.ctx.strokeStyle = color;
  dom.ctx.lineWidth = 3;
  dom.ctx.beginPath();
  dom.ctx.arc(scaledX, scaledY, 22, 0, 2 * Math.PI * (angle / 360));
  dom.ctx.stroke();
}
EOF

echo -e "${BLUE}→ Writing src/sources/demo.js…${NC}"
cat > src/sources/demo.js <<'EOF'
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
      phase: armL.currentPhase,
      atBottom: armL.currentPhase === 'up' && primaryL < (exercise.repThresholds?.flex ?? 80) + 15,
      ...formContextExtrasL,
    });
    const formR = exercise.checkForm({
      elbowAngle: primaryR, kneeAngle: primaryR,
      shoulderAngle: secondaryR, hipAngle: secondaryR,
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
EOF

# --- index.html update ---
echo -e "${BLUE}→ Updating index.html (adding exercise selector)…${NC}"
# Use a marker line to insert the dropdown
python3 - <<'PYEOF' || perl -pi -e 's|<span class="tag">MUSCLEMAP · v0.3[^<]*</span>|<span class="tag">MUSCLEMAP · v0.4 · MULTI-EXERCISE + FORM FEEDBACK</span>|' index.html
import re, sys
with open('index.html', 'r') as f:
    html = f.read()

# Update the version tag
html = re.sub(
    r'<span class="tag">MUSCLEMAP · v0\.3[^<]*</span>',
    '<span class="tag">MUSCLEMAP · v0.4 · MULTI-EXERCISE + FORM FEEDBACK</span>',
    html
)

# Insert exercise picker right after the subtitle paragraph (idempotent)
if 'exercise-picker' not in html:
    html = html.replace(
        '<p class="subtitle">Live webcam or uploaded video. Bilateral tracking, asymmetry scoring, real-time form feedback.</p>',
        '<p class="subtitle">Live webcam or uploaded video. Bilateral tracking, asymmetry scoring, real-time form feedback.</p>\n\n    <div class="exercise-picker">\n      <label for="exerciseSelect">EXERCISE:</label>\n      <select id="exerciseSelect"></select>\n    </div>'
    )

with open('index.html', 'w') as f:
    f.write(html)
print('index.html updated')
PYEOF

# --- CSS append ---
echo -e "${BLUE}→ Appending styles to src/ui/styles.css…${NC}"
if ! grep -q "exercise-picker" src/ui/styles.css; then
  cat >> src/ui/styles.css <<'EOF'

/* --- Exercise picker --- */
.exercise-picker {
  display: flex; align-items: center; gap: 10px;
  margin-bottom: 16px;
}
.exercise-picker label {
  font-family: 'Menlo', monospace;
  font-size: 10px; letter-spacing: 0.15em;
  color: var(--text-dim);
}
.exercise-picker select {
  background: var(--panel);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 8px 14px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  font-family: inherit;
}
.exercise-picker select:focus {
  outline: none;
  border-color: var(--accent);
}
EOF
  echo -e "${GREEN}  ✓${NC} styles appended"
else
  echo -e "${YELLOW}  ⚠ exercise-picker styles already present, skipping${NC}"
fi

# --- Commit ---
echo ""
echo -e "${BLUE}→ Committing changes…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit — files may already be up to date${NC}"
else
  git commit -q -m "feat: add squat exercise with form-rule engine

- New squat module with 5 form rules: depth, valgus, forward lean,
  L/R asymmetry, stance width
- Squat activation model (quads, glutes, hamstrings, erectors)
- Rep detector refactored to accept exercise-specific thresholds
- UI: exercise selector dropdown, dynamic muscle labels
- Demo mode supports both curl and squat"
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Squat feature applied          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it locally:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  Open http://localhost:5173, click the EXERCISE dropdown,"
echo -e "  pick 'Squat', click Demo — watch the form-feedback catch valgus"
echo ""
echo -e "${YELLOW}When you're happy, merge to main:${NC}"
echo ""
echo -e "  ${BLUE}git push -u origin feat/squat-exercise${NC}"
echo -e "  ${BLUE}git checkout main${NC}"
echo -e "  ${BLUE}git merge feat/squat-exercise${NC}"
echo -e "  ${BLUE}git push${NC}"
echo -e "  ${BLUE}git branch -d feat/squat-exercise${NC}"
echo ""
echo -e "${YELLOW}If something's wrong and you want to throw this work away:${NC}"
echo ""
echo -e "  ${BLUE}git checkout main${NC}"
echo -e "  ${BLUE}git branch -D feat/squat-exercise${NC}"
echo ""
