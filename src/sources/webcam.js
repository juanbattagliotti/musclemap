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
