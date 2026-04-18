export function computeAsymmetry(armL, armR) {
  const nL = armL.repPeaks.length;
  const nR = armR.repPeaks.length;
  const minReps = Math.min(nL, nR);
  if (minReps < 1) return { signed: 0, abs: 0, verdict: null };

  const window = Math.min(minReps, 5);
  const mean = (arr) => arr.slice(-window).reduce((a, b) => a + b, 0) / window;
  const meanL = mean(armL.repPeaks);
  const meanR = mean(armR.repPeaks);
  const avg = (meanL + meanR) / 2;
  if (avg === 0) return { signed: 0, abs: 0, verdict: null };

  const signed = (meanR - meanL) / avg;
  const abs = Math.abs(signed);

  let verdict;
  if (abs < 0.05) verdict = { severity: 'balanced', label: 'WELL BALANCED' };
  else if (abs < 0.12) verdict = { severity: 'mild', label: (signed > 0 ? 'R' : 'L') + ' SLIGHTLY STRONGER' };
  else verdict = { severity: 'notable', label: (signed > 0 ? 'R' : 'L') + ' NOTABLY STRONGER' };

  return { signed, abs, verdict };
}
