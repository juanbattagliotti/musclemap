import { PoseLandmarker, FilesetResolver, DrawingUtils } from '@mediapipe/tasks-vision';

const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task';
const WASM_URL = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.9/wasm';

export async function loadPoseLandmarker(onProgress = () => {}) {
  onProgress('wasm');
  const vision = await FilesetResolver.forVisionTasks(WASM_URL);

  onProgress('model');
  const landmarker = await PoseLandmarker.createFromOptions(vision, {
    baseOptions: { modelAssetPath: MODEL_URL, delegate: 'GPU' },
    runningMode: 'VIDEO',
    numPoses: 1
  });

  return { landmarker, utils: { PoseLandmarker, DrawingUtils } };
}
