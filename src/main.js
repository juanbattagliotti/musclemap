import { loadPoseLandmarker } from './pose/loader.js';
import { dom, log } from './ui/dom.js';
import { renderMuscleList, updateBodyDiagram, setStatus, setPoseStatus,
         updateRepUI, updateAsymmetryUI, updateFormBanner, clearOverlay,
         showSource, hideSource, drawLandmarksAndConnectors, drawAngleArc,
         setMuscleLabels, setExerciseTitle } from './ui/render.js';
import { makeArmState, resetArmState } from './analytics/session-state.js';
import { detectRep, isAtBottom } from './analytics/rep-detector.js';
import { makeSetState, startSet as startSetFn, endSet as endSetFn,
         recordRep, computeFatigue, rirLabel, summarizeSet } from './analytics/fatigue.js';
import { computeAsymmetry } from './analytics/asymmetry.js';
import { getExercise, listExercises } from './exercises/index.js';
import { startWebcam, stopWebcam } from './sources/webcam.js';
import { startUploadedVideo } from './sources/video-upload.js';
import { runDemo, stopDemo } from './sources/demo.js';
import { paintBodyOverlay } from './ui/body-overlay.js';
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
const setL = makeSetState();
const setR = makeSetState();
let setActive = false;
let overlayEnabled = true;

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
  if (dom.startSetBtn) dom.startSetBtn.addEventListener('click', onStartSet);
  if (dom.endSetBtn) dom.endSetBtn.addEventListener('click', onEndSet);
  if (dom.overlayToggle) dom.overlayToggle.addEventListener('click', onToggleOverlay);

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
  bindCueLearnMore();
  updateSetButtons();
  updateFatigueUI();

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
  renderGuide(getGuide(id));
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
  Object.assign(setL, makeSetState());
  Object.assign(setR, makeSetState());
  setActive = false;
  updateFatigueUI();
  updateSetButtons();
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
  updateFormBannerWithEducation(null, getCueEducation);
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
      updateFormBannerWithEducation(mergeFormVerdicts(formL, formR), getCueEducation);
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
  updateFormBannerWithEducation(null, getCueEducation);
  setStatus('SELECT INPUT SOURCE', 'loading');
  mode = null;
}

function predictLoop() {
  if (!running) return;

  // Defensive: if the canvas never got sized, size it now
  if ((dom.overlay.width === 0 || dom.overlay.height === 0) && dom.video.videoWidth > 0) {
    dom.overlay.width = dom.video.videoWidth;
    dom.overlay.height = dom.video.videoHeight;
  }

  if (poseLandmarker && dom.video.currentTime !== lastVideoTime && dom.video.readyState >= 2) {
    lastVideoTime = dom.video.currentTime;
    const now = performance.now();

    try {
      const result = poseLandmarker.detectForVideo(dom.video, now);
      clearOverlay();

      if (result.landmarks && result.landmarks.length > 0) {
        const lm = result.landmarks[0];
        drawLandmarksAndConnectors(drawingUtils, poseUtils.PoseLandmarker, lm);

        // Body overlay — paint activation-colored muscle shapes over the video
        // Computed once we have both sides' activations (see below)

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

        // Paint the body overlay first so that UI chrome (angle arcs, etc)
        // draws on top of it
        paintBodyOverlay(dom.ctx, currentExercise.id, lm, dom.overlay.width, dom.overlay.height,
                         resultL.activations, resultR.activations, overlayEnabled);

        renderMuscleList(dom.muscleListLEl, resultL.activations, false);
        renderMuscleList(dom.muscleListREl, resultR.activations, true);
        updateBodyDiagram(resultL.activations, resultR.activations);
        updateRepUI(armL, armR);
        updateAsymmetryUI(computeAsymmetry(armL, armR));
        updateFormBannerWithEducation(mergeFormVerdicts(resultL.formCheck, resultR.formCheck), getCueEducation);
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
  const repRecord = detectRep(armState, primaryAngle, primaryAct, formCheck, exercise.repThresholds, timestamp);
  if (repRecord && setActive) {
    const setState = armState === armL ? setL : setR;
    recordRep(setState, repRecord);
  }

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
  // Prefer the side with more reps for the set summary (single-set report for now)
  const primarySet = setL.reps.length >= setR.reps.length ? setL : setR;
  const setSummary = primarySet.reps.length > 0 ? summarizeSet(primarySet) : null;
  const summary = buildSessionSummary(armL, armR, currentExercise, {
    clientName: dom.clientNameInput?.value || '',
    trainerName: dom.trainerNameInput?.value || '',
    notes: dom.notesInput?.value || '',
  }, setSummary);
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


function onStartSet() {
  startSetFn(setL);
  startSetFn(setR);
  setActive = true;
  updateSetButtons();
  updateFatigueUI();
  log('set started — tracking fatigue', 'ok');
}

function onEndSet() {
  endSetFn(setL);
  endSetFn(setR);
  setActive = false;
  updateSetButtons();
  updateFatigueUI();
  const sL = summarizeSet(setL);
  const sR = summarizeSet(setR);
  const totalReps = (sL?.totalReps || 0) + (sR?.totalReps || 0);
  const lossL = sL ? Math.round(sL.finalVelLoss * 100) : 0;
  const lossR = sR ? Math.round(sR.finalVelLoss * 100) : 0;
  log('set ended — ' + totalReps + ' reps · vel loss L ' + lossL + '% · R ' + lossR + '%', 'ok');
}

function updateSetButtons() {
  if (dom.startSetBtn) {
    dom.startSetBtn.disabled = setActive;
    dom.startSetBtn.textContent = setActive ? 'Set active…' : 'Start set';
  }
  if (dom.endSetBtn) {
    dom.endSetBtn.style.display = setActive ? 'inline-block' : 'none';
  }
}

function updateFatigueUI() {
  if (!dom.fatigueWrap) return;

  if (!setActive && setL.reps.length === 0 && setR.reps.length === 0) {
    dom.fatigueWrap.classList.add('inactive');
    dom.fatigueStatus.textContent = 'NO SET ACTIVE';
    dom.rirValue.textContent = '—';
    dom.fatigueFill.style.width = '0%';
    dom.fatigueFill.className = 'fatigue-fill';
    dom.velLossValue.textContent = '—';
    return;
  }

  dom.fatigueWrap.classList.remove('inactive');

  // Use the side with more reps as the primary display
  const primarySet = setL.reps.length >= setR.reps.length ? setL : setR;
  const result = computeFatigue(primarySet);

  if (result.rir === null) {
    dom.fatigueStatus.textContent = 'BASELINING…';
    dom.rirValue.textContent = '—';
    dom.fatigueFill.style.width = '5%';
    dom.fatigueFill.className = 'fatigue-fill';
    dom.velLossValue.textContent = '—';
    return;
  }

  const { label, severity } = rirLabel(result.rir);
  dom.fatigueStatus.textContent = label;
  dom.fatigueStatus.dataset.severity = severity;

  // RIR display — round to nearest half
  const rirDisplay = Math.round(result.rir * 2) / 2;
  dom.rirValue.textContent = rirDisplay;

  // Fatigue bar fill
  const fillPct = Math.min(100, result.fatigue * 100 / 0.4 * 100);
  dom.fatigueFill.style.width = Math.min(100, result.fatigue / 0.4 * 100) + '%';
  dom.fatigueFill.className = 'fatigue-fill ' + severity;

  // Velocity loss
  const velLossPct = Math.round(result.signals.velLoss * 100);
  dom.velLossValue.textContent = velLossPct + '%';
}


function onToggleOverlay() {
  overlayEnabled = !overlayEnabled;
  if (dom.overlayToggle) {
    dom.overlayToggle.textContent = overlayEnabled ? 'Overlay: ON' : 'Overlay: OFF';
    dom.overlayToggle.classList.toggle('active', overlayEnabled);
  }
  log('body overlay ' + (overlayEnabled ? 'enabled' : 'disabled'), 'ok');
}

init();
