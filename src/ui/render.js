import { dom } from './dom.js';

const MUSCLE_META = [
  { key: 'bicep', label: 'Biceps brachii' },
  { key: 'deltoid', label: 'Ant. deltoid' },
  { key: 'forearm', label: 'Forearm flex.' }
];

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
  MUSCLE_META.forEach(m => {
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
  set('muscle-ldelt', actsL.deltoid, false);
  set('muscle-lbicep', actsL.bicep, false);
  set('muscle-lforearm', actsL.forearm, false);
  set('muscle-rdelt', actsR.deltoid, true);
  set('muscle-rbicep', actsR.bicep, true);
  set('muscle-rforearm', actsR.forearm, true);
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
