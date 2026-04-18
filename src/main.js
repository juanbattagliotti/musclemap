import { loadPoseLandmarker } from './pose/loader.js';
import { dom, log } from './ui/dom.js';
import { renderMuscleList, updateBodyDiagram, setStatus, setPoseStatus,
         updateRepUI, updateAsymmetryUI, updateFormBanner, clearOverlay,
         showSource, hideSource, drawLandmarksAndConnectors, drawAngleArc } from './ui/render.js';
import { makeArmState, resetArmState, updateArmData } from './analytics/session-state.js';
import { detectRep } from './analytics/rep-detector.js';
import { computeAsymmetry } from './analytics/asymmetry.js';
import { getExercise } from './exercises/index.js';
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

const currentExercise = getExercise('bicepCurl');
const armL = makeArmState();
const armR = makeArmState();

async function init() {
  log('prototype v0.3 ready — form feedback enabled');

  dom.startBtn.addEventListener('click', onStartWebcam);
  dom.videoFileInput.addEventListener('change', onVideoFile);
  dom.resetBtn.addEventListener('click', onReset);
  dom.demoBtn.addEventListener('click', onDemo);
  dom.stopBtn.addEventListener('click', onStop);

  const empty = { bicep: 0, deltoid: 0, forearm: 0 };
  renderMuscleList(dom.muscleListLEl, empty, false);
  renderMuscleList(dom.muscleListREl, empty, true);
  updateBodyDiagram(empty, empty);

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
  const empty = { bicep: 0, deltoid: 0, forearm: 0 };
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
  log('session reset', 'ok');
}

function onDemo() {
  if (running) onStop();
  mode = 'demo';
  running = true;
  showSource('DEMO MODE');
  dom.stopBtn.style.display = 'inline-block';
  setStatus('SIMULATED CURL', '');
  log('demo — simulated bilateral curl with slight asymmetry', 'ok');

  runDemo(currentExercise, armL, armR, {
    onFrame: (actsL, actsR, elbowL, elbowR, formL, formR) => {
      dom.angleLEl.textContent = Math.round(elbowL) + '°';
      dom.angleREl.textContent = Math.round(elbowR) + '°';
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

        const { activations: actsL, formCheck: formL, elbowAngle: elbowL } =
          processArm(lm, currentExercise, armL, 'left', now);
        const { activations: actsR, formCheck: formR, elbowAngle: elbowR } =
          processArm(lm, currentExercise, armR, 'right', now);

        if (elbowL !== null) {
          dom.angleLEl.textContent = Math.round(elbowL) + '°';
          const landmarks = currentExercise.getKeypoints(lm, 'left');
          if (landmarks) drawAngleArc(landmarks.elbow, elbowL, formL?.color || '#00ff9d');
        }
        if (elbowR !== null) {
          dom.angleREl.textContent = Math.round(elbowR) + '°';
          const landmarks = currentExercise.getKeypoints(lm, 'right');
          if (landmarks) drawAngleArc(landmarks.elbow, elbowR, formR?.color || '#ffd166');
        }

        renderMuscleList(dom.muscleListLEl, actsL, false);
        renderMuscleList(dom.muscleListREl, actsR, true);
        updateBodyDiagram(actsL, actsR);
        updateRepUI(armL, armR);
        updateAsymmetryUI(computeAsymmetry(armL, armR));
        updateFormBanner(mergeFormVerdicts(formL, formR));
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

function processArm(landmarks, exercise, armState, side, timestamp) {
  const keypoints = exercise.getKeypoints(landmarks, side);
  if (!keypoints) return { activations: { bicep: 0, deltoid: 0, forearm: 0 }, formCheck: null, elbowAngle: null };

  const { elbowAngle, shoulderAngle } = exercise.computeAngles(keypoints);
  const activations = updateArmData(armState, elbowAngle, shoulderAngle, timestamp, exercise.estimateActivations);
  const formCheck = exercise.checkForm({ elbowAngle, shoulderAngle, phase: armState.currentPhase });
  detectRep(armState, elbowAngle, activations.bicep, formCheck);

  return { activations, formCheck, elbowAngle };
}

function mergeFormVerdicts(formL, formR) {
  if (!formL && !formR) return null;
  const order = { bad: 3, warning: 2, good: 1 };
  const worst = [formL, formR].filter(Boolean)
    .sort((a, b) => order[b.verdict] - order[a.verdict])[0];
  return worst;
}

init();
