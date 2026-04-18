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
  document.getElementById('overlay').classList.add('mirrored');
  await videoEl.play();

  const overlay = document.getElementById('overlay');
  const sizeCanvas = () => {
    overlay.width = videoEl.videoWidth || 640;
    overlay.height = videoEl.videoHeight || 480;
  };
  sizeCanvas();
  videoEl.addEventListener('loadedmetadata', sizeCanvas);

  return { stream };
}

export function stopWebcam(stream) {
  if (stream) stream.getTracks().forEach(t => t.stop());
}
