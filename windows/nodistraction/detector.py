"""Riconoscimento del volto e dello sguardo con MediaPipe Face Landmarker.

Stessa logica e stesse soglie di chrome-extension/detector.js.
"""

from __future__ import annotations

import math
import statistics
import threading
from dataclasses import dataclass

import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions, vision

CALIBRATION_SAMPLES = 45
# Con questi landmark il pitch relativo aumenta quando il mento scende.
PAUSE_PITCH_DOWN = 14.0
PAUSE_PITCH_UP = -14.0
PAUSE_YAW_DELTA = 0.13
EYES_CLOSED = 0.55
EYES_LOOK_AWAY = 0.62


@dataclass(frozen=True)
class GazeResult:
    face: bool
    calibrating: bool
    progress: int = 100
    # None quando stai guardando lo schermo.
    away_reason: str | None = None


def _estimate_pitch(landmarks) -> float:
    forehead, chin = landmarks[10], landmarks[152]
    vertical = max(0.0001, chin.y - forehead.y)
    return math.degrees(math.atan2(chin.z - forehead.z, vertical))


def _estimate_yaw(landmarks) -> float:
    nose, left, right = landmarks[1], landmarks[234], landmarks[454]
    return (nose.x - left.x) / max(0.0001, right.x - left.x)


def _look_away_reason(pitch_delta: float, yaw_delta: float, scores: dict[str, float]) -> str | None:
    def both(first: str, second: str) -> float:
        return min(scores.get(first, 0.0), scores.get(second, 0.0))

    if abs(yaw_delta) > PAUSE_YAW_DELTA:
        return "Testa girata"
    if pitch_delta > PAUSE_PITCH_DOWN:
        return "Testa abbassata"
    if pitch_delta < PAUSE_PITCH_UP:
        return "Testa alzata"
    if both("eyeBlinkLeft", "eyeBlinkRight") > EYES_CLOSED:
        return "Occhi chiusi"
    if both("eyeLookDownLeft", "eyeLookDownRight") > EYES_LOOK_AWAY:
        return "Sguardo in basso"
    if both("eyeLookOutLeft", "eyeLookInRight") > EYES_LOOK_AWAY:
        return "Sguardo di lato"
    if both("eyeLookInLeft", "eyeLookOutRight") > EYES_LOOK_AWAY:
        return "Sguardo di lato"
    return None


class GazeDetector:
    """Analizza i fotogrammi sul thread della webcam; `recalibrate` può arrivare
    dal thread dell'interfaccia, per questo lo stato è protetto da un lock."""

    def __init__(self, model_path: str):
        options = vision.FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=model_path),
            running_mode=vision.RunningMode.VIDEO,
            num_faces=1,
            output_face_blendshapes=True,
            min_face_detection_confidence=0.45,
            min_face_presence_confidence=0.45,
            min_tracking_confidence=0.45,
        )
        self._landmarker = vision.FaceLandmarker.create_from_options(options)
        self._lock = threading.Lock()
        self._last_timestamp = -1
        self.recalibrate()

    def recalibrate(self) -> None:
        with self._lock:
            self._pitch_samples: list[float] = []
            self._yaw_samples: list[float] = []
            self._pitch_baseline: float | None = None
            self._yaw_baseline: float | None = None
            self._filtered_pitch: float | None = None

    def close(self) -> None:
        self._landmarker.close()

    def analyze(self, rgb: np.ndarray, timestamp_ms: int) -> GazeResult:
        # MediaPipe in modalità VIDEO vuole timestamp strettamente crescenti.
        timestamp_ms = max(timestamp_ms, self._last_timestamp + 1)
        self._last_timestamp = timestamp_ms
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(rgb))
        result = self._landmarker.detect_for_video(image, timestamp_ms)

        with self._lock:
            if not result.face_landmarks:
                return GazeResult(face=False, calibrating=self._pitch_baseline is None, progress=0)

            landmarks = result.face_landmarks[0]
            raw_pitch = _estimate_pitch(landmarks)
            yaw = _estimate_yaw(landmarks)
            if self._filtered_pitch is None:
                self._filtered_pitch = raw_pitch
            else:
                self._filtered_pitch = 0.20 * raw_pitch + 0.80 * self._filtered_pitch

            if self._pitch_baseline is None:
                self._pitch_samples.append(self._filtered_pitch)
                self._yaw_samples.append(yaw)
                progress = min(100, round(len(self._pitch_samples) / CALIBRATION_SAMPLES * 100))
                if len(self._pitch_samples) >= CALIBRATION_SAMPLES:
                    self._pitch_baseline = statistics.median(self._pitch_samples)
                    self._yaw_baseline = statistics.median(self._yaw_samples)
                return GazeResult(face=True, calibrating=True, progress=progress)

            scores = {
                category.category_name: category.score
                for category in (result.face_blendshapes[0] if result.face_blendshapes else [])
            }
            pitch_delta = self._filtered_pitch - self._pitch_baseline
            reason = _look_away_reason(pitch_delta, yaw - self._yaw_baseline, scores)
            return GazeResult(face=True, calibrating=False, away_reason=reason)
