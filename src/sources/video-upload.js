export function startUploadedVideo(videoEl, url, onEnded) {
  return new Promise((resolve, reject) => {
    videoEl.srcObject = null;
    videoEl.src = url;
    videoEl.muted = true;
    videoEl.playsInline = true;
    videoEl.classList.remove('mirrored');
    document.getElementById('overlay').classList.remove('mirrored');

    videoEl.onloadedmetadata = async () => {
      const overlay = document.getElementById('overlay');
      overlay.width = videoEl.videoWidth || 640;
      overlay.height = videoEl.videoHeight || 480;
      try {
        await videoEl.play();
        resolve();
      } catch (e) { reject(e); }
    };
    videoEl.onended = onEnded || (() => {});
  });
}
