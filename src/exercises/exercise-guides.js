// =========================================================================
// Exercise reference content — description, muscles involved, execution
// notes, and an SVG execution diagram. Kept separate from the exercise's
// computational module so content can be edited without touching logic.
//
// Educational content is hand-written and references to injury-risk stats
// are drawn from strength-coaching literature. Where we cite specific
// numbers, the source is noted; trainers can verify.
// =========================================================================

export const EXERCISE_GUIDES = {
  bicepCurl: {
    name: 'Bicep Curl',
    description:
      'Elbow flexion against resistance. Primary hypertrophy target for the biceps brachii. A staple of upper-body programming; often loaded too heavily, leading to shoulder compensation that shifts load away from the target tissue.',
    execution: [
      'Stand upright, feet hip-width apart. Dumbbells at sides, palms facing forward (supinated grip).',
      'Keeping elbows pinned to the torso, flex at the elbow to bring the weight toward the shoulder.',
      'Pause briefly at full flexion, then lower under control over 2–3 seconds.',
      'Avoid shoulder flexion — if the elbow moves forward, load is shifting to the anterior deltoid.',
    ],
    muscles: {
      primary: ['Biceps brachii (short + long head)', 'Brachialis (deeper, underneath)'],
      secondary: ['Brachioradialis (forearm)', 'Anterior deltoid (stabilizer)'],
    },
    diagram: bicepCurlDiagram(),
  },

  squat: {
    name: 'Squat',
    description:
      'Compound lower-body movement. Hip and knee flex simultaneously while the spine stays neutral. The single most informative movement for lower-body strength and mobility assessment. Form errors tend to cluster: valgus, depth, and trunk lean are the big three.',
    execution: [
      'Feet shoulder-width apart, toes slightly turned out (~15°).',
      'Initiate by pushing the hips back and bending the knees simultaneously.',
      'Descend until thighs are at least parallel to the floor (or deeper, based on mobility).',
      'Drive through the mid-foot to stand, keeping the knees tracking over the toes.',
    ],
    muscles: {
      primary: ['Quadriceps (all four heads)', 'Gluteus maximus', 'Adductor magnus'],
      secondary: ['Hamstrings', 'Erector spinae (spinal stabilization)', 'Calves (ankle stability)'],
    },
    diagram: squatDiagram(),
  },
};

// --- Form rule educational content ---
//
// Keyed by the cue text. When a form rule fires with a matching cue, the
// "Learn more" button surfaces this explanation. Blank for cues we don't
// have solid references for — better to omit than make things up.

export const CUE_EDUCATION = {
  'Stop swinging — pin your elbows to your sides.':
    'Shoulder flexion during a curl shifts mechanical tension from the biceps to the anterior deltoid and reduces stimulus to the target muscle. If the client can\'t complete the rep without swinging, the load is too heavy for their current strength level.',

  'Keep your shoulder still. Isolate the biceps.':
    'Even small amounts of shoulder flexion (>25°) redistribute work to accessory muscles. For hypertrophy-focused training, strict form with lighter load generally outperforms heavy-but-loose reps.',

  'Curl higher — bring the weight all the way up.':
    'Partial range-of-motion reps reduce time under tension at the biomechanically strongest portion of the lift. Full ROM also maintains joint mobility, which is especially relevant for clients with desk-based lifestyles.',

  'Extend fully at the bottom — full range of motion.':
    'Shortened reps at the bottom of the curl limit stretch on the biceps long head, reducing the hypertrophic stimulus. Full extension also strengthens the tendon at end-range where most injuries occur.',

  'Avoid fully locking your elbow — keep a slight bend.':
    'Hyperextending the elbow under load shifts tensile stress from muscle to the joint capsule and ligaments. Maintaining a 5–10° bend keeps the load on the contractile tissue.',

  'Squat deeper — aim for thighs parallel to the floor.':
    'Depth matters for glute activation — EMG studies consistently show gluteus maximus activation increases substantially past parallel. Shallow squats preferentially load the quadriceps and under-develop the posterior chain. (Caterisano et al., 2002, J Strength Cond Res.)',

  'Push your knees OUT — stop them caving inward.':
    'Dynamic knee valgus under load is associated with ~4–6x increased risk of non-contact ACL injury (Hewett et al., 2005, Am J Sports Med). The typical cause is gluteus medius weakness allowing the femur to internally rotate. Cue: "spread the floor" with the feet.',

  'Watch your knees — drive them slightly outward, tracking your toes.':
    'Mild valgus under light load is usually a motor-control issue rather than a strength deficit. Cueing external rotation at the hip ("screw your feet into the floor") often resolves it without additional exercises.',

  'Chest up! Too much forward lean — engage your core.':
    'Excessive forward trunk lean increases shear force on the lumbar spine and can indicate limited ankle dorsiflexion, tight hip flexors, or core instability. If the client can\'t squat upright even without load, mobility work precedes loading.',

  'Keep your chest proud — reduce the forward lean.':
    'Some forward lean is normal and biomechanically necessary; the issue is when it\'s excessive or asymmetric. For most lifters, the torso angle roughly matches the tibia angle — if trunk is leaning more than shin, something is off.',

  'You\'re shifting — load both legs evenly.':
    'Bilateral asymmetry during squats is often compensation for a prior injury or a dominant-side bias. Worth noting for tracking over time — asymmetry that persists across sessions warrants unilateral work (split squats, lunges) to rebalance.',

  'Widen your stance — feet about shoulder-width apart.':
    'Very narrow stance increases the demand on ankle mobility and shifts emphasis toward the quadriceps while reducing glute involvement. For most general-population clients, hip- to shoulder-width is the default starting point.',

  'Stance is very wide — narrow it for a standard squat.':
    'Wide-stance squats (sumo) bias adductors and glutes and reduce the need for ankle mobility, but they\'re a variation, not the default. For assessment, a standard-width squat gives more generalizable information.',
};

// =========================================================================
// SVG diagrams — simple line-art execution references.
// Drawn with inline strings to avoid needing image assets.
// =========================================================================
function bicepCurlDiagram() {
  return `
    <svg viewBox="0 0 180 220" xmlns="http://www.w3.org/2000/svg" class="guide-diagram">
      <!-- Three-phase diagram: start / mid / end -->
      <g stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <!-- START pose: arm extended at side -->
        <g transform="translate(20,20)">
          <circle cx="15" cy="10" r="7"/>
          <line x1="15" y1="17" x2="15" y2="55"/>
          <line x1="15" y1="22" x2="8" y2="60"/>
          <line x1="8" y1="60" x2="6" y2="95"/>
          <line x1="6" y1="95" x2="4" y2="125"/>
          <circle cx="4" cy="127" r="3" fill="currentColor"/>
          <text x="0" y="160" font-size="8" fill="currentColor" opacity="0.6">START</text>
        </g>
        <!-- MID pose: forearm raising -->
        <g transform="translate(70,20)">
          <circle cx="15" cy="10" r="7"/>
          <line x1="15" y1="17" x2="15" y2="55"/>
          <line x1="15" y1="22" x2="8" y2="60"/>
          <line x1="8" y1="60" x2="16" y2="80"/>
          <line x1="16" y1="80" x2="22" y2="70"/>
          <circle cx="22" cy="70" r="3" fill="currentColor"/>
          <text x="0" y="160" font-size="8" fill="currentColor" opacity="0.6">MID</text>
        </g>
        <!-- TOP pose: full flexion -->
        <g transform="translate(120,20)">
          <circle cx="15" cy="10" r="7"/>
          <line x1="15" y1="17" x2="15" y2="55"/>
          <line x1="15" y1="22" x2="8" y2="60"/>
          <line x1="8" y1="60" x2="20" y2="30"/>
          <circle cx="20" cy="30" r="3" fill="currentColor"/>
          <text x="0" y="160" font-size="8" fill="currentColor" opacity="0.6">TOP</text>
        </g>
      </g>
    </svg>
  `;
}

function squatDiagram() {
  return `
    <svg viewBox="0 0 180 220" xmlns="http://www.w3.org/2000/svg" class="guide-diagram">
      <g stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round">
        <!-- START pose: standing -->
        <g transform="translate(20,20)">
          <circle cx="15" cy="10" r="7"/>
          <line x1="15" y1="17" x2="15" y2="65"/>
          <line x1="15" y1="65" x2="8" y2="105"/>
          <line x1="15" y1="65" x2="22" y2="105"/>
          <line x1="8" y1="105" x2="6" y2="145"/>
          <line x1="22" y1="105" x2="24" y2="145"/>
          <text x="0" y="175" font-size="8" fill="currentColor" opacity="0.6">START</text>
        </g>
        <!-- BOTTOM pose: parallel -->
        <g transform="translate(70,20)">
          <circle cx="18" cy="30" r="7"/>
          <line x1="18" y1="37" x2="12" y2="75"/>
          <line x1="12" y1="75" x2="28" y2="90"/>
          <line x1="12" y1="75" x2="28" y2="92"/>
          <line x1="28" y1="90" x2="5" y2="125"/>
          <line x1="28" y1="92" x2="14" y2="145"/>
          <line x1="5" y1="125" x2="2" y2="145"/>
          <text x="0" y="175" font-size="8" fill="currentColor" opacity="0.6">BOTTOM</text>
        </g>
        <!-- END: back to standing -->
        <g transform="translate(120,20)">
          <circle cx="15" cy="10" r="7"/>
          <line x1="15" y1="17" x2="15" y2="65"/>
          <line x1="15" y1="65" x2="8" y2="105"/>
          <line x1="15" y1="65" x2="22" y2="105"/>
          <line x1="8" y1="105" x2="6" y2="145"/>
          <line x1="22" y1="105" x2="24" y2="145"/>
          <text x="0" y="175" font-size="8" fill="currentColor" opacity="0.6">END</text>
        </g>
      </g>
    </svg>
  `;
}

export function getGuide(exerciseId) {
  return EXERCISE_GUIDES[exerciseId] || null;
}

export function getCueEducation(cue) {
  if (!cue) return null;
  return CUE_EDUCATION[cue] || null;
}
