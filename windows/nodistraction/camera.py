"""Elenco delle webcam e acquisizione dei fotogrammi in un thread."""

from __future__ import annotations

import re
import sys
import threading
import time
from dataclasses import dataclass
from typing import Callable

import cv2
import numpy as np

# Webcam virtuali (OBS ecc.) scartate in automatico: senza il programma che le
# alimenta mandano un'immagine fissa.
VIRTUAL_CAMERA = re.compile(r"obs|virtual|snap camera|mmhmm|manycam|xsplit|ndi|droidcam|iriun|camo", re.I)
FRAMES_PER_SECOND = 10


@dataclass(frozen=True)
class CameraInfo:
    index: int
    name: str

    @property
    def is_virtual(self) -> bool:
        return bool(VIRTUAL_CAMERA.search(self.name))


def available_cameras() -> list[CameraInfo]:
    if sys.platform == "win32":
        try:
            # DirectShow elenca i dispositivi nello stesso ordine usato da OpenCV con CAP_DSHOW.
            from pygrabber.dshow_graph import FilterGraph

            names = FilterGraph().get_input_devices()
            return [CameraInfo(index, name) for index, name in enumerate(names)]
        except Exception:
            pass
    return [CameraInfo(0, "Webcam predefinita")]


def choose_camera(cameras: list[CameraInfo], preferred_name: str) -> CameraInfo | None:
    """La webcam scelta per nome; altrimenti la prima non virtuale."""
    for camera in cameras:
        if camera.name == preferred_name:
            return camera
    return next((c for c in cameras if not c.is_virtual), cameras[0] if cameras else None)


class CameraError(Exception):
    pass


class CameraWorker:
    """Legge la webcam a FRAMES_PER_SECOND e passa ogni fotogramma RGB a `on_frame`."""

    def __init__(self, camera: CameraInfo, on_frame: Callable[[np.ndarray, int], None]):
        self.camera = camera
        self._on_frame = on_frame
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._capture: cv2.VideoCapture | None = None
        self.latest_frame: np.ndarray | None = None

    def start(self) -> None:
        backend = cv2.CAP_DSHOW if sys.platform == "win32" else cv2.CAP_ANY
        capture = cv2.VideoCapture(self.camera.index, backend)
        if not capture.isOpened():
            capture.release()
            raise CameraError(
                "Impossibile aprire la webcam. Controlla che non sia usata da un'altra app "
                "e che Windows permetta l'accesso: Impostazioni › Privacy e sicurezza › Fotocamera."
            )
        capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        self._capture = capture
        self._thread = threading.Thread(target=self._run, name="camera", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
        if self._capture:
            self._capture.release()
        self.latest_frame = None

    def _run(self) -> None:
        interval = 1 / FRAMES_PER_SECOND
        failures = 0
        while not self._stop.is_set():
            started = time.monotonic()
            ok, frame = self._capture.read()
            if not ok:
                failures += 1
                if failures > 30:
                    break
                time.sleep(0.1)
                continue
            failures = 0
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            self.latest_frame = rgb
            self._on_frame(rgb, int(time.monotonic() * 1000))
            time.sleep(max(0.0, interval - (time.monotonic() - started)))
