#!/usr/bin/env bash
# =============================================================================
# MuscleMap — fix/webcam-canvas-sizing
#
# Bug: when webcam starts, canvas is sized before the video element has its
# real dimensions. Result: skeleton draws to a 0x0 or tiny canvas, invisible.
# Fix: wait for video metadata/playing events before sizing canvas, and
# defensively re-size every frame if dimensions are still missing.
# =============================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   MuscleMap — fix webcam canvas size   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

if [ ! -f "package.json" ] || [ ! -d "src" ]; then
  echo -e "${RED}✗ Run this from inside the musclemap folder.${NC}"; exit 1
fi
if ! git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Uncommitted changes. Commit or stash first.${NC}"; exit 1
fi

CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT" != "main" ]; then
  echo -e "${YELLOW}⚠ Switching to main first…${NC}"
  git checkout main
fi

if git show-ref --verify --quiet refs/heads/fix/webcam-canvas-sizing; then
  git branch -D fix/webcam-canvas-sizing
fi
git checkout -b fix/webcam-canvas-sizing

echo -e "${BLUE}→ Rewriting src/sources/webcam.js…${NC}"
cat > src/sources/webcam.js <<'EOF'
// =========================================================================
// Webcam source — robust canvas sizing.
//
// Previous bug: we sized the canvas in sizeCanvas() immediately after
// video.play(), but videoWidth/videoHeight can still be 0 at that moment.
// MediaPipe would then draw to a 0x0 canvas and the skeleton was invisible.
//
// Fix: wait for 'loadedmetadata' AND 'playing' events, and also keep
// sizing defensively on 'resize' of the video element.
// =========================================================================

export async function startWebcam(videoEl) {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    throw new Error('mediaDevices not available — serve over https:// or localhost');
  }

  const stream = await navigator.mediaDevices.getUserMedia({
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
    audio: false
  });

  videoEl.srcObject = stream;
  videoEl.classList.add('mirrored');
  const overlay = document.getElementById('overlay');
  overlay.classList.add('mirrored');

  // Force autoplay + inline attributes that some browsers require
  videoEl.autoplay = true;
  videoEl.playsInline = true;
  videoEl.muted = true;

  await videoEl.play();

  // Canvas sizing — try multiple trigger points, whichever fires first wins.
  const sizeCanvas = () => {
    const w = videoEl.videoWidth;
    const h = videoEl.videoHeight;
    if (w > 0 && h > 0) {
      if (overlay.width !== w) overlay.width = w;
      if (overlay.height !== h) overlay.height = h;
    }
  };

  // Try immediately — sometimes metadata is already there
  sizeCanvas();

  // And on every likely event — harmless to bind all of them
  videoEl.addEventListener('loadedmetadata', sizeCanvas);
  videoEl.addEventListener('loadeddata', sizeCanvas);
  videoEl.addEventListener('playing', sizeCanvas);
  videoEl.addEventListener('resize', sizeCanvas);

  // Also poll for the first few frames in case none of the above fire
  // (edge cases on some browsers / camera drivers)
  let tries = 0;
  const poll = setInterval(() => {
    sizeCanvas();
    tries++;
    if ((overlay.width > 0 && overlay.height > 0) || tries > 30) {
      clearInterval(poll);
    }
  }, 100);

  return { stream };
}

export function stopWebcam(stream) {
  if (stream) stream.getTracks().forEach(t => t.stop());
}
EOF

echo -e "${BLUE}→ Adding a defensive re-size in the predict loop…${NC}"
python3 <<'PYEOF'
with open('src/main.js', 'r') as f:
    src = f.read()

# Add an extra safety check at the top of predictLoop() — if the overlay
# has 0 dimensions but the video does, fix it on the spot.
marker = "function predictLoop() {\n  if (!running) return;"
fix = """function predictLoop() {
  if (!running) return;

  // Defensive: if the canvas never got sized, size it now
  if ((dom.overlay.width === 0 || dom.overlay.height === 0) && dom.video.videoWidth > 0) {
    dom.overlay.width = dom.video.videoWidth;
    dom.overlay.height = dom.video.videoHeight;
  }"""

if "Defensive: if the canvas never got sized" not in src:
    src = src.replace(marker, fix)

with open('src/main.js', 'w') as f:
    f.write(src)
print('src/main.js patched')
PYEOF

echo ""
echo -e "${BLUE}→ Committing…${NC}"
git add .
if git diff-index --quiet HEAD --; then
  echo -e "${YELLOW}⚠ Nothing to commit${NC}"
else
  git commit -q -m "fix: webcam canvas sizing race

Bug: when webcam starts, canvas was sized immediately after video.play()
but videoWidth/Height can still be 0 at that moment. The skeleton was
drawing to a 0x0 canvas and was invisible.

Fix:
- Bind sizeCanvas to loadedmetadata, loadeddata, playing, resize events
- Poll every 100ms for the first 3 seconds as a fallback
- Added defensive re-size check at the top of the predict loop"
  echo -e "${GREEN}✓${NC} Committed"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Webcam fix applied           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Test it:${NC}"
echo -e "  ${BLUE}npm run dev${NC}"
echo -e "  Hard-refresh the browser (Cmd+Shift+R), click Start webcam."
echo -e "  You should now see the green skeleton + muscle overlay colors."
echo ""
echo -e "${YELLOW}Merge when good:${NC}"
echo -e "  ${BLUE}git push -u origin fix/webcam-canvas-sizing${NC}"
echo -e "  ${BLUE}git checkout main && git merge fix/webcam-canvas-sizing${NC}"
echo -e "  ${BLUE}git push && git branch -d fix/webcam-canvas-sizing${NC}"
echo ""
