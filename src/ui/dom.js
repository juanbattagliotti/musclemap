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

  reportBtn: $('reportBtn'),

  startSetBtn: $('startSetBtn'),
  endSetBtn: $('endSetBtn'),
  fatigueWrap: $('fatigueWrap'),
  fatigueStatus: $('fatigueStatus'),
  rirValue: $('rirValue'),
  fatigueFill: $('fatigueFill'),
  velLossValue: $('velLossValue'),
  clientNameInput: $('clientName'),
  trainerNameInput: $('trainerName'),
  notesInput: $('sessionNotes'),

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
