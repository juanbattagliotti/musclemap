import { bicepCurl } from './bicep-curl.js';
import { squat } from './squat.js';

const registry = {
  bicepCurl,
  squat,
};

export function getExercise(id) {
  const ex = registry[id];
  if (!ex) throw new Error('Unknown exercise: ' + id);
  return ex;
}

export function listExercises() {
  return Object.keys(registry).map(id => ({ id, name: registry[id].name }));
}
