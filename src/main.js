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
import { buildSessionSummary } from './analytics/session-summary.js';
import { generateSessionReport } from './reports/pdf-report.js';

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
  if (dom.reportBtn) dom.reportBtn.addEventListener('click', onGenerateReport);

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


function onGenerateReport() {
  const summary = buildSessionSummary(armL, armR, currentExercise, {
    clientName: dom.clientNameInput?.value || '',
    trainerName: dom.trainerNameInput?.value || '',
    notes: dom.notesInput?.value || '',
  });
  if (!summary) {
    log('no reps recorded yet — nothing to report', 'err');
    return;
  }
  const doc = generateSessionReport(summary);
  const filename = buildFilename(summary);
  doc.save(filename);
  log('report saved: ' + filename, 'ok');
}

function buildFilename(summary) {
  const d = summary.meta.date;
  const pad = (n) => String(n).padStart(2, '0');
  const datePart = d.getFullYear() + pad(d.getMonth()+1) + pad(d.getDate());
  const timePart = pad(d.getHours()) + pad(d.getMinutes());
  const exercise = summary.meta.exerciseId;
  const client = (summary.meta.clientName || 'session').replace(/[^a-z0-9]+/gi, '-').toLowerCase();
  return `musclemap_${exercise}_${client}_${datePart}-${timePart}.pdf`;
}

init();
