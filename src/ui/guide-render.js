import { dom } from './dom.js';

// =========================================================================
// Render the Exercise Guide panel
// =========================================================================
export function renderGuide(guide) {
  if (!dom.guideWrap) return;
  if (!guide) {
    dom.guideWrap.style.display = 'none';
    return;
  }
  dom.guideWrap.style.display = 'block';
  dom.guideName.textContent = guide.name;
  dom.guideDescription.textContent = guide.description;
  dom.guideDiagram.innerHTML = guide.diagram;

  dom.guideExecution.innerHTML = '';
  guide.execution.forEach((step, i) => {
    const li = document.createElement('li');
    li.innerHTML = '<span class="step-num">' + (i + 1) + '</span>' + step;
    dom.guideExecution.appendChild(li);
  });

  dom.guidePrimary.innerHTML = guide.muscles.primary
    .map(m => '<span class="muscle-chip primary">' + m + '</span>').join('');
  dom.guideSecondary.innerHTML = guide.muscles.secondary
    .map(m => '<span class="muscle-chip secondary">' + m + '</span>').join('');
}

// =========================================================================
// Form banner with "Learn more" button and expandable education blurb
// =========================================================================
let currentEducation = null;

export function updateFormBannerWithEducation(formCheck, getCueEducationFn) {
  if (!formCheck) {
    dom.formBanner.style.display = 'none';
    if (dom.formEducation) dom.formEducation.style.display = 'none';
    currentEducation = null;
    return;
  }
  dom.formBanner.style.display = 'block';
  dom.formBanner.className = 'form-banner ' + formCheck.verdict;
  dom.formVerdictEl.textContent = formCheck.verdictLabel;
  dom.formCueEl.textContent = formCheck.cue || '';

  currentEducation = getCueEducationFn(formCheck.cue);

  if (dom.formLearnMoreBtn) {
    if (currentEducation && formCheck.cue) {
      dom.formLearnMoreBtn.style.display = 'inline-block';
      dom.formLearnMoreBtn.textContent = 'Learn more';
    } else {
      dom.formLearnMoreBtn.style.display = 'none';
    }
  }
  if (dom.formEducation) {
    // Keep education hidden by default; user clicks to expand
    dom.formEducation.style.display = 'none';
    dom.formEducation.textContent = '';
  }
}

export function bindCueLearnMore() {
  if (!dom.formLearnMoreBtn || !dom.formEducation) return;
  dom.formLearnMoreBtn.addEventListener('click', () => {
    if (!currentEducation) return;
    const isOpen = dom.formEducation.style.display === 'block';
    if (isOpen) {
      dom.formEducation.style.display = 'none';
      dom.formLearnMoreBtn.textContent = 'Learn more';
    } else {
      dom.formEducation.textContent = currentEducation;
      dom.formEducation.style.display = 'block';
      dom.formLearnMoreBtn.textContent = 'Hide';
    }
  });
}
