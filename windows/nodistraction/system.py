"""Integrazioni con il sistema: impostazioni, avvio con Windows, suono,
istanza singola, percorsi delle risorse."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
RUN_VALUE = "No Distraction"


def resource_path(name: str) -> Path:
    """Risorse accanto al codice, sia in sviluppo sia nell'eseguibile PyInstaller."""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return base / "assets" / name


def settings_dir() -> Path:
    root = os.environ.get("APPDATA") or Path.home() / ".config"
    path = Path(root) / "NoDistraction"
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass
class Settings:
    pause_delay: float = 1.5
    auto_resume: bool = True
    pause_sound: bool = True
    auto_start: bool = True
    camera_name: str = ""

    @classmethod
    def load(cls) -> "Settings":
        try:
            data = json.loads((settings_dir() / "settings.json").read_text("utf-8"))
            known = {k: v for k, v in data.items() if k in cls.__dataclass_fields__}
            return cls(**known)
        except (OSError, ValueError, TypeError):
            return cls()

    def save(self) -> None:
        (settings_dir() / "settings.json").write_text(json.dumps(asdict(self), indent=2), "utf-8")


def launch_command() -> str:
    if getattr(sys, "frozen", False):
        return f"\"{sys.executable}\" --background"
    return f"\"{sys.executable}\" -m nodistraction --background"


def is_start_with_windows() -> bool:
    if sys.platform != "win32":
        return False
    import winreg

    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            winreg.QueryValueEx(key, RUN_VALUE)
            return True
    except OSError:
        return False


def set_start_with_windows(enabled: bool) -> None:
    if sys.platform != "win32":
        return
    import winreg

    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
        if enabled:
            winreg.SetValueEx(key, RUN_VALUE, 0, winreg.REG_SZ, launch_command())
        else:
            try:
                winreg.DeleteValue(key, RUN_VALUE)
            except OSError:
                pass


def play_error_sound() -> None:
    path = resource_path("error.wav")
    if sys.platform == "win32":
        import winsound

        winsound.PlaySound(str(path), winsound.SND_FILENAME | winsound.SND_ASYNC)
    elif sys.platform == "darwin":
        import subprocess

        subprocess.Popen(["afplay", str(path)])


_mutex = None


def acquire_single_instance() -> bool:
    """False se No Distraction è già in esecuzione."""
    global _mutex
    if sys.platform != "win32":
        return True
    import ctypes

    _mutex = ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\NoDistraction.SingleInstance")
    return ctypes.windll.kernel32.GetLastError() != 183  # ERROR_ALREADY_EXISTS
