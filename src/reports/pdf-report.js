import { jsPDF } from 'jspdf';

// =========================================================================
// Generate a one-page PDF session report.
// Takes a session summary (from buildSessionSummary) and returns a jsPDF
// instance ready to save.
// =========================================================================

const COLORS = {
  text: '#0c1220',
  textDim: '#5a6070',
  accent: '#00c878',
  warn: '#e67700',
  bad: '#d63838',
  rule: '#dde2ec',
  panel: '#f6f8fb',
};

export function generateSessionReport(summary, opts = {}) {
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  const M = 40;  // margin

  let y = M;

  // ---- Header bar ----
  doc.setFillColor(12, 18, 32);
  doc.rect(0, 0, W, 70, 'F');
  doc.setTextColor('#ffffff');
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(20);
  doc.text('MUSCLEMAP', M, 35);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor('#8090a0');
  doc.text('Movement analysis · Session report', M, 52);

  // Date top-right
  doc.setTextColor('#c0c8d4');
  doc.setFontSize(10);
  const dateStr = summary.meta.date.toLocaleDateString('en-GB', {
    year: 'numeric', month: 'long', day: 'numeric'
  });
  doc.text(dateStr, W - M, 35, { align: 'right' });
  doc.setFontSize(9);
  doc.setTextColor('#8090a0');
  doc.text(summary.meta.date.toLocaleTimeString('en-GB', {
    hour: '2-digit', minute: '2-digit'
  }), W - M, 52, { align: 'right' });

  y = 90;

  // ---- Session metadata ----
  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(16);
  doc.text(summary.meta.exercise, M, y);
  y += 20;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(10);
  doc.setTextColor(COLORS.textDim);
  const metaLine = [];
  if (summary.meta.clientName) metaLine.push('Client: ' + summary.meta.clientName);
  if (summary.meta.trainerName) metaLine.push('Trainer: ' + summary.meta.trainerName);
  if (metaLine.length) {
    doc.text(metaLine.join('   ·   '), M, y);
    y += 15;
  }

  y += 8;
  drawRule(doc, M, y, W - M);
  y += 18;

  // ---- Top metrics row (3 panels) ----
  const panelWidth = (W - M * 2 - 20) / 3;
  drawMetricPanel(doc, M, y, panelWidth, 70,
    'TOTAL REPS', String(summary.totals.totalReps),
    summary.totals.repsL + ' left · ' + summary.totals.repsR + ' right');

  drawMetricPanel(doc, M + panelWidth + 10, y, panelWidth, 70,
    'FORM SCORE', summary.totals.formScore + '%',
    scoreDescriptor(summary.totals.formScore),
    scoreColor(summary.totals.formScore));

  drawMetricPanel(doc, M + (panelWidth + 10) * 2, y, panelWidth, 70,
    'ASYMMETRY', summary.asymmetry.index + '%',
    summary.asymmetry.verdict,
    asymmetryColor(summary.asymmetry.index));

  y += 90;

  // ---- Form breakdown ----
  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('FORM BREAKDOWN', M, y);
  y += 14;

  const total = summary.totals.totalReps;
  const good = summary.totals.goodFormReps;
  const warn = summary.totals.warningFormReps;
  const bad  = summary.totals.badFormReps;

  drawStackedBar(doc, M, y, W - M * 2, 16, [
    { value: good, color: COLORS.accent, label: 'Clean' },
    { value: warn, color: COLORS.warn, label: 'Warning' },
    { value: bad,  color: COLORS.bad,   label: 'Bad' },
  ], total);
  y += 22;

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(COLORS.textDim);
  doc.text(
    good + ' clean    ' + warn + ' with warnings    ' + bad + ' with issues',
    M, y
  );
  y += 20;

  // ---- Per-side breakdown ----
  drawRule(doc, M, y, W - M);
  y += 18;

  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('PER-SIDE SUMMARY', M, y);
  y += 14;

  const colW = (W - M * 2 - 15) / 2;
  const sideY = y;
  drawSidePanel(doc, M,             sideY, colW, 'LEFT',  summary.left,  COLORS.accent);
  drawSidePanel(doc, M + colW + 15, sideY, colW, 'RIGHT', summary.right, '#e6a900');
  y = sideY + 75;

  // ---- Rep timeline ----
  drawRule(doc, M, y, W - M);
  y += 18;

  doc.setTextColor(COLORS.text);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11);
  doc.text('REP-BY-REP TIMELINE', M, y);
  y += 14;

  drawRepTimeline(doc, M, y, W - M * 2, 60, summary.timeline);
  y += 70;

  // Legend
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text('Bar height = peak activation for that rep · Color = form verdict', M, y);
  y += 14;

  // Key
  drawLegendDot(doc, M, y, COLORS.accent); doc.text('Clean', M + 10, y + 3);
  drawLegendDot(doc, M + 55, y, COLORS.warn); doc.text('Warning', M + 65, y + 3);
  drawLegendDot(doc, M + 120, y, COLORS.bad); doc.text('Bad', M + 130, y + 3);
  y += 18;

  // ---- Set summary ----
  if (summary.setSummary) {
    drawRule(doc, M, y, W - M);
    y += 18;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(COLORS.text);
    doc.text('SET SUMMARY', M, y);
    y += 14;
    const s = summary.setSummary;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(COLORS.textDim);
    const lossPct = Math.round(s.finalVelLoss * 100);
    const rirStr = s.estimatedFinalRIR !== null ? s.estimatedFinalRIR.toFixed(1) : 'n/a';
    doc.text('Reps completed: ' + s.totalReps + '     Velocity loss: ' + lossPct + '%     Estimated final RIR: ' + rirStr, M, y);
    y += 14;

    // Mini velocity chart
    const chartW = W - M * 2;
    const chartH = 35;
    const maxV = Math.max(...s.velocities, 0.001);
    const barW = Math.max(2, Math.min(16, chartW / Math.max(s.velocities.length, 1) - 2));
    s.velocities.forEach((v, i) => {
      const barH = (v / maxV) * chartH;
      const bx = M + i * (barW + 2);
      const by = y + chartH - barH;
      doc.setFillColor(COLORS.accent);
      doc.rect(bx, by, barW, barH, 'F');
    });
    y += chartH + 8;
    doc.setFontSize(8);
    doc.setTextColor(COLORS.textDim);
    doc.text('Rep-by-rep concentric velocity (higher = faster, velocity loss = fatigue)', M, y);
    y += 18;
  }

  // ---- Notes ----
  if (summary.meta.notes) {
    drawRule(doc, M, y, W - M);
    y += 18;
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(11);
    doc.setTextColor(COLORS.text);
    doc.text('NOTES', M, y);
    y += 14;
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(10);
    doc.setTextColor(COLORS.textDim);
    const notes = doc.splitTextToSize(summary.meta.notes, W - M * 2);
    doc.text(notes, M, y);
    y += notes.length * 12 + 10;
  }

  // ---- Footer ----
  doc.setFontSize(8);
  doc.setTextColor('#a0a8b8');
  doc.text('Generated by MuscleMap · Rule-based activation estimate, not clinical EMG',
    W / 2, H - 20, { align: 'center' });

  return doc;
}

// -------------------------------------------------------------------------
// Drawing helpers
// -------------------------------------------------------------------------

function drawRule(doc, x, y, x2) {
  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.line(x, y, x2, y);
}

function drawMetricPanel(doc, x, y, w, h, label, value, sublabel, valueColor) {
  doc.setFillColor(COLORS.panel);
  doc.roundedRect(x, y, w, h, 6, 6, 'F');

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text(label, x + 12, y + 16);

  doc.setFont('helvetica', 'bold');
  doc.setFontSize(24);
  doc.setTextColor(valueColor || COLORS.text);
  doc.text(value, x + 12, y + 44);

  if (sublabel) {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(9);
    doc.setTextColor(COLORS.textDim);
    doc.text(sublabel, x + 12, y + 60);
  }
}

function drawStackedBar(doc, x, y, w, h, segments, total) {
  let cursor = x;
  segments.forEach(seg => {
    const segW = total > 0 ? (seg.value / total) * w : 0;
    if (segW > 0) {
      doc.setFillColor(seg.color);
      doc.rect(cursor, y, segW, h, 'F');
      cursor += segW;
    }
  });
  // outline
  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.rect(x, y, w, h);
}

function drawSidePanel(doc, x, y, w, label, side, accentColor) {
  doc.setFillColor(COLORS.panel);
  doc.roundedRect(x, y, w, 70, 6, 6, 'F');

  // Label
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9);
  doc.setTextColor(accentColor);
  doc.text(label, x + 12, y + 15);

  // Rep count
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(14);
  doc.setTextColor(COLORS.text);
  doc.text(side.reps + ' reps', x + 12, y + 35);

  // Details
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9);
  doc.setTextColor(COLORS.textDim);
  doc.text('Avg peak: ' + side.avgPeak + '%', x + 12, y + 50);
  doc.text('Avg ROM: ' + side.avgROM[0] + '–' + side.avgROM[1] + '°', x + 12, y + 62);

  // Good-rep badge (right side of panel)
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(18);
  doc.setTextColor(scoreColor(side.goodRepPct));
  doc.text(side.goodRepPct + '%', x + w - 12, y + 36, { align: 'right' });
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  doc.setTextColor(COLORS.textDim);
  doc.text('clean', x + w - 12, y + 50, { align: 'right' });
}

function drawRepTimeline(doc, x, y, w, h, timeline) {
  if (timeline.length === 0) return;

  const gap = 3;
  const barW = Math.max(2, Math.min(20, (w - gap * (timeline.length - 1)) / timeline.length));
  const maxPeak = Math.max(...timeline.map(r => r.peak), 0.1);

  doc.setDrawColor(COLORS.rule);
  doc.setLineWidth(0.5);
  doc.line(x, y + h, x + w, y + h);  // baseline

  timeline.forEach((rep, i) => {
    const barX = x + i * (barW + gap);
    const barH = (rep.peak / maxPeak) * h;
    const barY = y + h - barH;
    const color =
      rep.form === 'bad' ? COLORS.bad :
      rep.form === 'warning' ? COLORS.warn :
      (rep.side === 'L' ? COLORS.accent : '#e6a900');
    doc.setFillColor(color);
    doc.rect(barX, barY, barW, barH, 'F');
  });
}

function drawLegendDot(doc, x, y, color) {
  doc.setFillColor(color);
  doc.circle(x + 4, y, 3, 'F');
}

function scoreColor(pct) {
  if (pct >= 80) return COLORS.accent;
  if (pct >= 60) return COLORS.warn;
  return COLORS.bad;
}
function scoreDescriptor(pct) {
  if (pct >= 90) return 'Excellent';
  if (pct >= 75) return 'Good';
  if (pct >= 60) return 'Needs work';
  return 'Needs attention';
}
function asymmetryColor(pct) {
  if (pct < 5) return COLORS.accent;
  if (pct < 12) return COLORS.warn;
  return COLORS.bad;
}
