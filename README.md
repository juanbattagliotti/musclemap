# MuscleMap

Biomechanics-informed coaching software for personal trainers.
Single-phone pose estimation + muscle activation analysis + real-time form feedback.

## Status

Early prototype — web-based, runs entirely in-browser via MediaPipe.

## Quick start

```bash
npm install
npm run dev
```

Open http://localhost:5173

## Features

- Bilateral pose tracking (MediaPipe BlazePose)
- Rule-based muscle activation estimation
- Rep detection, range-of-motion tracking, fatigue curves
- Left/right asymmetry scoring
- Real-time form feedback with traffic-light coloring
- Works with live webcam or uploaded video

## Supported exercises

- Bicep curl
- Squat (in progress)

## Architecture

See [docs/architecture.md](docs/architecture.md).

## License

Not open source — internal development only.
