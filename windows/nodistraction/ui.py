"""Finestra di No Distraction: stesso contenuto e stessa disposizione del
pannello dell'app per Mac."""

from __future__ import annotations

import math
import sys
from typing import Callable

import customtkinter as ctk
from PIL import Image

from . import APP_NAME
from .system import resource_path

ACCENT = ("#5B4BF5", "#6E63FF")
ACCENT_HOVER = ("#4A3AE0", "#5B4BF5")
STOP = ("#D9363E", "#E5484D")
STOP_HOVER = ("#B92D34", "#C93B40")
GROUP_BG = ("#ECEBF3", "#232230")
MUTED = ("#6B6880", "#9C99B0")
COLORS = {
    "green": ("#1F9D55", "#3DD68C"),
    "orange": ("#C26A00", "#FFB224"),
    "red": ("#D9363E", "#FF6369"),
    "muted": MUTED,
}

DELAY_MIN, DELAY_MAX = 0.3, 30.0
WIDTH = 360


def delay_step(value: float) -> float:
    if value < 3:
        return 0.1
    if value < 10:
        return 0.5
    return 1.0


def round_delay(value: float) -> float:
    step = delay_step(value)
    result = round(round(value / step) * step, 1)
    return min(max(result, DELAY_MIN), DELAY_MAX)


def format_delay(value: float) -> str:
    if value >= 10 or abs(value - round(value)) < 0.05:
        return f"{round(value)} s"
    return f"{value:.1f} s".replace(".", ",")


class Group(ctk.CTkFrame):
    """Riquadro con titolo, come i gruppi delle impostazioni."""

    def __init__(self, master, title: str):
        super().__init__(master, fg_color="transparent")
        ctk.CTkLabel(self, text=title.upper(), font=ctk.CTkFont(size=11, weight="bold"),
                     text_color=MUTED, anchor="w").pack(fill="x", padx=6)
        frame = ctk.CTkFrame(self, fg_color=GROUP_BG, corner_radius=10)
        frame.pack(fill="x", pady=(4, 0))
        # Contenitore interno: il margine verticale qui evita spaziatori che
        # coprirebbero gli angoli arrotondati.
        self.body = ctk.CTkFrame(frame, fg_color="transparent")
        self.body.pack(fill="x", padx=4, pady=6)

    def switch(self, text: str, variable: ctk.BooleanVar, command: Callable[[], None]) -> ctk.CTkSwitch:
        row = ctk.CTkFrame(self.body, fg_color="transparent")
        row.pack(fill="x", padx=8, pady=5)
        ctk.CTkLabel(row, text=text, anchor="w", font=ctk.CTkFont(size=13)).pack(side="left")
        switch = ctk.CTkSwitch(row, text="", variable=variable, command=command, width=40,
                               progress_color=ACCENT, button_color="#FFFFFF", button_hover_color="#F2F1F7",
                               fg_color=("#C9C6D8", "#4A4858"))
        switch.pack(side="right")
        return switch


class MainWindow(ctk.CTk):
    def __init__(self, controller):
        super().__init__()
        self.controller = controller
        settings = controller.settings
        ctk.set_appearance_mode("system")

        self.title(APP_NAME)
        self.resizable(False, False)
        self.configure(fg_color=("#F7F6FB", "#18171F"))
        icon_path = resource_path("icon.ico")
        if sys.platform == "win32" and icon_path.exists():
            self.iconbitmap(str(icon_path))
        # Chiudere la finestra la nasconde: l'app resta nell'area di notifica.
        self.protocol("WM_DELETE_WINDOW", self.withdraw)
        self.bind("<Escape>", lambda _: self.withdraw())

        self.icon_image = ctk.CTkImage(Image.open(resource_path("icon.png")), size=(42, 42))
        outer = ctk.CTkFrame(self, fg_color="transparent")
        outer.pack(fill="both", padx=16, pady=16)
        self.outer = outer

        # Intestazione.
        header = ctk.CTkFrame(outer, fg_color="transparent")
        header.pack(fill="x")
        ctk.CTkLabel(header, text="", image=self.icon_image).pack(side="left", padx=(0, 12))
        titles = ctk.CTkFrame(header, fg_color="transparent")
        titles.pack(side="left", fill="x", expand=True)
        ctk.CTkLabel(titles, text=APP_NAME, font=ctk.CTkFont(size=16, weight="bold"), anchor="w").pack(fill="x")
        self.status_label = ctk.CTkLabel(titles, text="Non attivo", anchor="w", justify="left",
                                         text_color=MUTED, wraplength=260, font=ctk.CTkFont(size=12))
        self.status_label.pack(fill="x")

        buttons = ctk.CTkFrame(outer, fg_color="transparent")
        buttons.pack(fill="x", pady=(12, 0))
        self.main_button = ctk.CTkButton(buttons, text="▶  Avvia", height=36, corner_radius=8,
                                         font=ctk.CTkFont(size=14, weight="bold"),
                                         fg_color=ACCENT, hover_color=ACCENT_HOVER, command=controller.toggle)
        self.main_button.pack(side="left", fill="x", expand=True)
        self.recalibrate_button = ctk.CTkButton(buttons, text="⌖", width=40, height=36, corner_radius=8,
                                                font=ctk.CTkFont(size=18), fg_color=GROUP_BG,
                                                text_color=("#2A2250", "#E8E6FF"), hover_color=("#DDDAF0", "#2E2C40"),
                                                command=controller.recalibrate)

        # Avviso (webcam non disponibile ecc.).
        self.notice = ctk.CTkFrame(outer, fg_color=("#FFF1DC", "#3A2A12"), corner_radius=10)
        self.notice_label = ctk.CTkLabel(self.notice, text="", wraplength=WIDTH - 60, justify="left",
                                         anchor="w", font=ctk.CTkFont(size=12))
        self.notice_label.pack(fill="x", padx=12, pady=10)

        # Anteprima della webcam.
        self.preview_size = (WIDTH - 32, round((WIDTH - 32) * 9 / 16))
        self.preview = ctk.CTkLabel(outer, text="", fg_color="#000000", corner_radius=12,
                                    width=self.preview_size[0], height=self.preview_size[1])

        self.content_anchor = ctk.CTkFrame(outer, fg_color="transparent", height=0)
        self.content_anchor.pack(fill="x")

        # Pausa.
        pause = Group(outer, "Pausa")
        pause.pack(fill="x", pady=(14, 0))
        delay_row = ctk.CTkFrame(pause.body, fg_color="transparent")
        delay_row.pack(fill="x", padx=8, pady=(4, 0))
        ctk.CTkLabel(delay_row, text="Metti in pausa dopo", font=ctk.CTkFont(size=13)).pack(side="left")
        small = dict(width=28, height=28, corner_radius=14, border_spacing=0, fg_color=("#DDDAF0", "#33313F"),
                     text_color=("#2A2250", "#E8E6FF"), hover_color=("#CFCBEA", "#403D52"),
                     font=ctk.CTkFont(size=14, weight="bold"))
        ctk.CTkButton(delay_row, text="+", command=lambda: self.nudge(1), **small).pack(side="right")
        self.delay_label = ctk.CTkLabel(delay_row, text="", width=52, font=ctk.CTkFont(size=14, weight="bold"))
        self.delay_label.pack(side="right", padx=4)
        ctk.CTkButton(delay_row, text="−", command=lambda: self.nudge(-1), **small).pack(side="right")
        self.delay_slider = ctk.CTkSlider(pause.body, from_=0, to=1, command=self.on_slider,
                                          progress_color=ACCENT, button_color=ACCENT, button_hover_color=ACCENT_HOVER)
        self.delay_slider.pack(fill="x", padx=8, pady=(8, 0))
        scale = ctk.CTkFrame(pause.body, fg_color="transparent")
        scale.pack(fill="x", padx=10)
        for text, side in ((format_delay(DELAY_MIN), "left"), (format_delay(DELAY_MAX), "right")):
            ctk.CTkLabel(scale, text=text, text_color=MUTED, font=ctk.CTkFont(size=10)).pack(side=side)
        ctk.CTkLabel(scale, text="più fine sui valori brevi", text_color=MUTED, font=ctk.CTkFont(size=10)).pack()
        ctk.CTkFrame(pause.body, height=1, fg_color=("#D8D5E8", "#33313F")).pack(fill="x", padx=8, pady=(2, 4))
        self.auto_resume = ctk.BooleanVar(value=settings.auto_resume)
        self.pause_sound = ctk.BooleanVar(value=settings.pause_sound)
        pause.switch("Riprendi quando torno a guardare", self.auto_resume, self.on_settings)
        pause.switch("Suono di errore alla pausa", self.pause_sound, self.on_settings)

        # Webcam.
        webcam = Group(outer, "Webcam")
        webcam.pack(fill="x", pady=(14, 0))
        self.camera_menu = ctk.CTkOptionMenu(webcam.body, values=["Automatica (esclude virtuali)"],
                                             command=self.on_camera, fg_color=("#FFFFFF", "#2E2C3A"),
                                             button_color=ACCENT, button_hover_color=ACCENT_HOVER,
                                             text_color=("#1E1550", "#E8E6FF"), dynamic_resizing=False)
        self.camera_menu.pack(fill="x", padx=8, pady=6)

        # Generale.
        general = Group(outer, "Generale")
        general.pack(fill="x", pady=(14, 0))
        self.auto_start = ctk.BooleanVar(value=settings.auto_start)
        self.start_with_windows = ctk.BooleanVar(value=controller.start_with_windows)
        general.switch("Attiva all'apertura dell'app", self.auto_start, self.on_settings)
        general.switch("Avvia con Windows", self.start_with_windows, self.on_start_with_windows)

        # Piè di pagina.
        footer = ctk.CTkFrame(outer, fg_color="transparent")
        footer.pack(fill="x", pady=(12, 0))
        self.footer_label = ctk.CTkLabel(footer, text="🔒  Analisi solo su questo PC", text_color=MUTED,
                                         anchor="w", justify="left", wraplength=260, font=ctk.CTkFont(size=11))
        self.footer_label.pack(side="left", fill="x", expand=True)
        ctk.CTkButton(footer, text="Esci", width=50, height=24, fg_color="transparent", text_color=MUTED,
                      hover_color=GROUP_BG, command=controller.quit).pack(side="right")

        self.set_delay(settings.pause_delay)
        self.refresh_cameras()

    # ----- Ritardo -----

    def set_delay(self, seconds: float) -> None:
        self.delay = round_delay(seconds)
        self.delay_label.configure(text=format_delay(self.delay))
        position = math.log(self.delay / DELAY_MIN) / math.log(DELAY_MAX / DELAY_MIN)
        self.delay_slider.set(position)

    def on_slider(self, position: float) -> None:
        seconds = round_delay(DELAY_MIN * (DELAY_MAX / DELAY_MIN) ** position)
        self.delay = seconds
        self.delay_label.configure(text=format_delay(seconds))
        self.on_settings()

    def nudge(self, direction: int) -> None:
        step = delay_step(self.delay if direction > 0 else self.delay - 0.001)
        self.set_delay(min(max(self.delay + direction * step, DELAY_MIN), DELAY_MAX))
        self.on_settings()

    # ----- Impostazioni -----

    def on_settings(self) -> None:
        self.controller.update_settings(
            pause_delay=self.delay,
            auto_resume=self.auto_resume.get(),
            pause_sound=self.pause_sound.get(),
            auto_start=self.auto_start.get(),
        )

    def on_start_with_windows(self) -> None:
        self.controller.set_start_with_windows(self.start_with_windows.get())

    def refresh_cameras(self) -> None:
        cameras = self.controller.cameras
        self._camera_names = {"Automatica (esclude virtuali)": ""}
        for camera in cameras:
            label = f"{camera.name} — virtuale" if camera.is_virtual else camera.name
            self._camera_names[label] = camera.name
        self.camera_menu.configure(values=list(self._camera_names))
        chosen = next((label for label, name in self._camera_names.items()
                       if name == self.controller.settings.camera_name), "Automatica (esclude virtuali)")
        self.camera_menu.set(chosen)

    def on_camera(self, label: str) -> None:
        self.controller.choose_camera(self._camera_names.get(label, ""))

    # ----- Stato -----

    def show_state(self, *, running: bool, status: str, color: str, notice: str | None, footer: str | None) -> None:
        self.status_label.configure(text=status, text_color=COLORS[color])
        if running:
            self.main_button.configure(text="■  Interrompi", fg_color=STOP, hover_color=STOP_HOVER)
            if not self.recalibrate_button.winfo_ismapped():
                self.recalibrate_button.pack(side="right", padx=(8, 0))
            if not self.preview.winfo_ismapped():
                self.preview.pack(fill="x", pady=(14, 0), before=self.content_anchor)
        else:
            self.main_button.configure(text="▶  Avvia", fg_color=ACCENT, hover_color=ACCENT_HOVER)
            self.recalibrate_button.pack_forget()
            self.preview.pack_forget()
        if notice:
            self.notice_label.configure(text="⚠️  " + notice)
            if not self.notice.winfo_ismapped():
                self.notice.pack(fill="x", pady=(12, 0), after=self.main_button.master)
        else:
            self.notice.pack_forget()
        self.footer_label.configure(text=footer or "🔒  Analisi solo su questo PC")

    def show_frame(self, rgb) -> None:
        if not self.preview.winfo_ismapped() or self.state() == "withdrawn":
            return
        image = Image.fromarray(rgb).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        # Riempie il riquadro 16:9 ritagliando al centro.
        target_w, target_h = self.preview_size
        scale = max(target_w / image.width, target_h / image.height)
        image = image.resize((round(image.width * scale), round(image.height * scale)))
        left = (image.width - target_w) // 2
        top = (image.height - target_h) // 2
        image = image.crop((left, top, left + target_w, top + target_h))
        self._preview_image = ctk.CTkImage(image, size=self.preview_size)
        self.preview.configure(image=self._preview_image)

    def show_near_tray(self) -> None:
        """Mostra la finestra in basso a destra, sopra la barra delle applicazioni."""
        self.update_idletasks()
        width, height = self.winfo_reqwidth(), self.winfo_reqheight()
        right, bottom = self.winfo_screenwidth(), self.winfo_screenheight()
        if sys.platform == "win32":
            import ctypes
            from ctypes import wintypes

            area = wintypes.RECT()
            ctypes.windll.user32.SystemParametersInfoW(48, 0, ctypes.byref(area), 0)  # SPI_GETWORKAREA
            right, bottom = area.right, area.bottom
        x = max(0, right - width - 16)
        y = max(0, bottom - height - 48)
        self.geometry(f"+{x}+{y}")
        self.deiconify()
        self.lift()
        self.focus_force()
