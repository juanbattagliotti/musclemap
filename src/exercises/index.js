import { bicepCurl } from './bicep-curl.js';

const registry = {
  bicepCurl,
};

export function getExercise(id) {
  const ex = registry[id];
  if (!ex) throw new Error('Unknown exercise: ' + id);
  return ex;
}

export function listExercises() {
  return Object.keys(registry).map(id => ({ id, name: registry[id].name }));
}
