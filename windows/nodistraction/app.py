"""Avvio, icona nell'area di notifica e logica di pausa (come AppModel su Mac)."""

from __future__ import annotations

import argparse
import queue
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

from . import APP_NAME, __version__
from .camera import CameraError, CameraWorker, available_cameras, choose_camera
from .detector import GazeDetector, GazeResult
from .media import MediaController
from .system import (
    Settings,
    acquire_single_instance,
    is_start_with_windows,
    play_error_sound,
    resource_path,
    set_start_with_windows,
)

RESUME_AFTER = 0.4  # secondi di sguardo sullo schermo prima di riprendere
DOT_COLORS = {"green": "#3DD68C", "orange": "#FFB224", "red": "#FF4964", "muted": "#9C99B0"}


def model_path() -> str:
    return str(resource_path("face_landmarker.task"))


def tray_image(color: str) -> Image.Image:
    """Icona dell'app con un pallino colorato che indica lo stato."""
    image = Image.open(resource_path("icon.png")).convert("RGBA").resize((64, 64), Image.LANCZOS)
    draw = ImageDraw.Draw(image)
    draw.ellipse((40, 40, 63, 63), fill=DOT_COLORS[color], outline="#FFFFFF", width=3)
    return image


class Controller:
    def __init__(self, show_window: bool):
        self.settings = Settings.load()
        self.start_with_windows = is_start_with_windows()
        self.cameras = available_cameras()
        self.media = MediaController()
        self.detector: GazeDetector | None = None
        self.worker: CameraWorker | None = None
        self.results: queue.Queue[GazeResult] = queue.Queue()
        self.commands: queue.Queue = queue.Queue()

        self.running = False
        self.phase = "off"  # off, calibrating, watching, away, paused, error
        self.reason: str | None = None
        self.progress = 0
        self.face_found = True
        self.error: str | None = None
        self.last_action: str | None = None
        self.videos_paused = False
        self.away_since: float | None = None
        self.back_since: float | None = None

        from .ui import MainWindow

        self.window = MainWindow(self)
        self.window.withdraw()
        self._setup_tray()
        self.window.after(50, self._poll)
        if show_window:
            self.window.after(200, self.window.show_near_tray)
        if self.settings.auto_start:
            self.window.after(300, self.start)
        self._render()

    # ----- Area di notifica -----

    def _setup_tray(self) -> None:
        if sys.platform != "win32":
            # Fuori da Windows (solo per sviluppo) niente icona: su Mac c'è l'app nativa.
            self.tray = _NoTray()
            return
        import pystray

        def call(fn):
            return lambda *_: self.commands.put(fn)

        self.tray = pystray.Icon(
            "NoDistraction",
            tray_image("muted"),
            APP_NAME,
            menu=pystray.Menu(
                pystray.MenuItem("Apri No Distraction", call(self.window.show_near_tray), default=True),
                pystray.MenuItem(lambda _: "Interrompi" if self.running else "Avvia", call(self.toggle)),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Esci", call(self.quit)),
            ),
        )
        self.tray.run_detached()

    # ----- Avvio e arresto -----

    def toggle(self) -> None:
        self.stop() if self.running else self.start()

    def start(self) -> None:
        if self.running:
            return
        self.error = None
        try:
            if self.detector is None:
                self.detector = GazeDetector(model_path())
            self.detector.recalibrate()
            camera = choose_camera(self.cameras, self.settings.camera_name)
            if camera is None:
                raise CameraError("Nessuna webcam trovata.")
            self.worker = CameraWorker(camera, self._on_frame)
            self.worker.start()
        except Exception as error:  # webcam o modello
            self.worker = None
            self.phase, self.error = "error", str(error)
            self._render()
            return
        self.running = True
        self.phase, self.progress, self.face_found = "calibrating", 0, True
        self.away_since = self.back_since = None
        self.last_action = camera.name
        self._render()

    def stop(self) -> None:
        if self.worker:
            self.worker.stop()
            self.worker = None
        self.running = False
        self.phase, self.reason = "off", None
        if self.videos_paused:
            self.videos_paused = False
            if self.settings.auto_resume:
                self._media(self.media.resume())
            else:
                self.media.forget()
        self._render()

    def recalibrate(self) -> None:
        if self.running and self.detector:
            self.detector.recalibrate()
            self.phase, self.progress = "calibrating", 0
            self._render()

    def quit(self) -> None:
        self.stop()
        self.tray.stop()
        self.window.destroy()

    # ----- Impostazioni -----

    def update_settings(self, **changes) -> None:
        for key, value in changes.items():
            setattr(self.settings, key, value)
        self.settings.save()

    def set_start_with_windows(self, enabled: bool) -> None:
        set_start_with_windows(enabled)
        self.start_with_windows = enabled

    def choose_camera(self, name: str) -> None:
        self.update_settings(camera_name=name)
        if self.running:
            self.stop()
            self.start()

    # ----- Analisi -----

    def _on_frame(self, rgb: np.ndarray, timestamp_ms: int) -> None:
        """Thread della webcam: analizza e passa il risultato all'interfaccia."""
        detector = self.detector
        if detector is not None:
            self.results.put(detector.analyze(rgb, timestamp_ms))

    def _poll(self) -> None:
        """Thread dell'interfaccia: comandi dall'icona, risultati, anteprima."""
        while not self.commands.empty():
            self.commands.get_nowait()()
        changed = False
        while not self.results.empty():
            self._handle(self.results.get_nowait())
            changed = True
        if self.worker and self.worker.latest_frame is not None:
            self.window.show_frame(self.worker.latest_frame)
        if self.worker and not self.worker._thread.is_alive() and self.running:
            self.stop()
            self.phase, self.error = "error", "La webcam ha smesso di inviare immagini."
            changed = True
        if changed:
            self._render()
        if self.window.winfo_exists():
            self.window.after(50, self._poll)

    def _handle(self, result: GazeResult) -> None:
        if not self.running:
            return
        now = time.monotonic()
        if result.calibrating:
            self.phase, self.progress, self.face_found = "calibrating", result.progress, result.face
            return
        reason = result.away_reason if result.face else "Volto assente"
        if reason:
            self.back_since = None
            self.away_since = self.away_since or now
            if not self.videos_paused and now - self.away_since >= self.settings.pause_delay:
                self._pause_media()
            self.phase, self.reason = ("paused" if self.videos_paused else "away"), reason
        else:
            self.away_since = None
            if self.videos_paused:
                self.back_since = self.back_since or now
                if now - self.back_since >= RESUME_AFTER:
                    self._resume_media()
            self.phase, self.reason = ("paused" if self.videos_paused else "watching"), None

    def _pause_media(self) -> None:
        self.videos_paused = True
        if self.settings.pause_sound:
            play_error_sound()
        self._media(self.media.pause())

    def _resume_media(self) -> None:
        self.videos_paused = False
        if self.settings.auto_resume:
            self._media(self.media.resume())
        else:
            self.media.forget()

    def _media(self, future) -> None:
        def done(f):
            try:
                message = f.result()
            except Exception as error:
                message = f"Errore controlli multimediali: {error}"
            if message:
                self.commands.put(lambda: self._set_last_action(message))

        future.add_done_callback(done)

    def _set_last_action(self, message: str) -> None:
        self.last_action = message
        self._render()

    # ----- Presentazione -----

    def _render(self) -> None:
        if self.phase == "off":
            status, color = "Non attivo", "muted"
        elif self.phase == "error":
            status, color = "Webcam non disponibile", "red"
        elif self.phase == "calibrating":
            status = f"Calibrazione {self.progress}% — guarda lo schermo" if self.face_found else "Volto non rilevato"
            color = "orange"
        elif self.phase == "watching":
            status, color = "Stai guardando", "green"
        elif self.phase == "away":
            status, color = f"{self.reason}…", "orange"
        else:
            status = f"In pausa — {self.reason}" if self.reason else "In pausa — torna a guardare"
            color = "red"
        self.window.show_state(running=self.running, status=status, color=color,
                               notice=self.error, footer=self.last_action)
        self.tray.icon = tray_image(color)
        self.tray.title = f"{APP_NAME} — {status}"


class _NoTray:
    icon = None
    title = ""

    def stop(self) -> None:
        pass


def self_test() -> int:
    """Controllo usato dalla build: modello, analisi, controlli multimediali, interfaccia."""
    print(f"{APP_NAME} {__version__} — auto-test")
    detector = GazeDetector(model_path())
    result = detector.analyze(np.zeros((480, 640, 3), np.uint8), 0)
    assert not result.face, result
    print("modello e analisi: ok")
    sessions = MediaController().describe_sessions()
    print(f"controlli multimediali: ok ({len(sessions)} sessioni)")
    for name in ("icon.png", "icon.ico", "error.wav"):
        assert resource_path(name).exists(), name
    import customtkinter  # noqa: F401  (incluso nel pacchetto)
    print("risorse: ok")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(prog="NoDistraction")
    parser.add_argument("--background", action="store_true", help="avvio senza mostrare la finestra")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--log", help="scrive l'output in questo file (l'exe non ha console)")
    args = parser.parse_args()

    if args.log:
        sys.stdout = sys.stderr = open(args.log, "w", encoding="utf-8", buffering=1)
    if args.self_test:
        try:
            code = self_test()
        except Exception:
            import traceback

            traceback.print_exc()
            code = 1
        sys.exit(code)

    if not acquire_single_instance():
        import ctypes

        ctypes.windll.user32.MessageBoxW(None, "No Distraction è già aperto: trovi l'icona nell'area di notifica.",
                                         APP_NAME, 0x40)
        return

    controller = Controller(show_window=not args.background)
    controller.window.mainloop()
