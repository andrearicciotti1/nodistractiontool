# -*- mode: python ; coding: utf-8 -*-
# PyInstaller: crea dist/NoDistraction/NoDistraction.exe (cartella, finestra senza console).
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

WINDOWS = Path(SPECPATH).parent

datas = [(str(WINDOWS / "assets"), "assets")]
datas += collect_data_files("mediapipe")
datas += collect_data_files("customtkinter")

hiddenimports = collect_submodules("winrt") + ["pystray._win32", "PIL._tkinter_finder"]

a = Analysis(
    [str(WINDOWS / "run.py")],
    pathex=[str(WINDOWS)],
    datas=datas,
    hiddenimports=hiddenimports,
    excludes=["IPython", "jupyter", "notebook", "pytest"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="NoDistraction",
    console=False,
    icon=str(WINDOWS / "assets" / "icon.ico"),
    version=str(WINDOWS / "build" / "version_info.txt"),
)
coll = COLLECT(exe, a.binaries, a.datas, name="NoDistraction")
