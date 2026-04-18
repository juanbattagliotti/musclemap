export function runFormRules(rules, context) {
  const violations = rules
    .map(rule => rule(context))
    .filter(v => v !== null);

  if (violations.length === 0) {
    return {
      verdict: 'good',
      verdictLabel: 'GOOD FORM',
      color: '#00ff9d',
      cue: ''
    };
  }

  violations.sort((a, b) => b.priority - a.priority);
  const top = violations[0];
  const colors = { warning: '#ffd166', bad: '#ff6b6b' };
  const labels = { warning: 'CHECK FORM', bad: 'FIX FORM' };

  return {
    verdict: top.verdict,
    verdictLabel: labels[top.verdict],
    color: colors[top.verdict],
    cue: top.cue
  };
}
