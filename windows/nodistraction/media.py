"""Pausa e ripresa di qualsiasi programma tramite i controlli multimediali di
Windows (Global System Media Transport Controls): gli stessi che compaiono
vicino al volume. A differenza del tasto ⏯ simulato su Mac, i comandi sono
espliciti (Pausa / Play) e si sa quale programma sta riproducendo."""

from __future__ import annotations

import asyncio
import sys
import threading
from concurrent.futures import Future


def friendly_name(app_id: str) -> str:
    """Da un AppUserModelID tipo 'Spotify.exe' o 'Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic'
    a un nome leggibile."""
    name = app_id.split("!")[-1]
    name = name.removesuffix(".exe").removesuffix(".EXE")
    known = {"chrome": "Google Chrome", "msedge": "Microsoft Edge", "firefox": "Firefox",
             "Microsoft.ZuneMusic": "Lettore multimediale", "vlc": "VLC"}
    return known.get(name, name.split(".")[-1] or app_id)


class MediaController:
    def __init__(self) -> None:
        self.available = sys.platform == "win32"
        self._paused_ids: set[str] = set()
        self._loop = asyncio.new_event_loop()
        threading.Thread(target=self._loop.run_forever, name="media", daemon=True).start()

    def pause(self) -> Future:
        """Mette in pausa ciò che sta suonando. Il Future restituisce un messaggio."""
        return asyncio.run_coroutine_threadsafe(self._pause(), self._loop)

    def resume(self) -> Future:
        return asyncio.run_coroutine_threadsafe(self._resume(), self._loop)

    def forget(self) -> None:
        self._paused_ids.clear()

    async def _sessions(self):
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
        )

        manager = await Manager.request_async()
        return list(manager.get_sessions())

    async def _pause(self) -> str:
        if not self.available:
            return "Controlli multimediali disponibili solo su Windows"
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
        )

        paused = []
        for session in await self._sessions():
            if session.get_playback_info().playback_status == Status.PLAYING:
                if await session.try_pause_async():
                    self._paused_ids.add(session.source_app_user_model_id)
                    paused.append(friendly_name(session.source_app_user_model_id))
        return f"In pausa: {', '.join(sorted(paused))}" if paused else "Niente in riproduzione"

    async def _resume(self) -> str:
        if not self.available or not self._paused_ids:
            return ""
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
        )

        resumed = []
        for session in await self._sessions():
            app_id = session.source_app_user_model_id
            # Solo ciò che abbiamo fermato noi e che nel frattempo è rimasto in pausa.
            if app_id in self._paused_ids and session.get_playback_info().playback_status == Status.PAUSED:
                if await session.try_play_async():
                    resumed.append(friendly_name(app_id))
        self._paused_ids.clear()
        return f"Ripreso: {', '.join(sorted(resumed))}" if resumed else "Già ripreso"

    def describe_sessions(self) -> list[str]:
        """Per l'auto-test: programmi che espongono controlli multimediali."""
        if not self.available:
            return []

        async def run():
            return [s.source_app_user_model_id for s in await self._sessions()]

        return asyncio.run_coroutine_threadsafe(run(), self._loop).result(timeout=10)
