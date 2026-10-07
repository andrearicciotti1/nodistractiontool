// Documento invisibile che tiene accesa la webcam e decide quando mettere in
// pausa i video. Vive finché il monitoraggio è attivo, anche senza schede
// dell’estensione aperte. Ha accesso solo a chrome.runtime: le schede le
// comanda il service worker.
import { Detector, cameraErrorHelp } from "./detector.js";

const RESUME_AFTER_MS = 400;
const STATE_INTERVAL_MS = 400;

const errorSound = new Audio(chrome.runtime.getURL("sounds/error.mp3"));

let settings = { cameraId: "", pauseDelay: 1500, autoResume: true, pauseSound: true };
let awaySince = null;
let backSince = null;
let videosPaused = false;
let state = { running: false };
let lastStateSent = 0;
let lastStateKey = "";

const detector = new Detector(handleResult);

function publish(patch, force = false) {
  state = { ...state, ...patch };
  const key = `${state.running}|${state.phase}|${state.reason}|${state.paused}|${state.progress}`;
  const now = performance.now();
  if (!force && key === lastStateKey && now - lastStateSent < STATE_INTERVAL_MS) return;
  lastStateKey = key;
  lastStateSent = now;
  chrome.runtime.sendMessage({ type: "ndt-state", state }).catch(() => {});
}

function setPaused(paused) {
  if (paused === videosPaused) return;
  videosPaused = paused;
  if (paused) {
    chrome.runtime.sendMessage({ type: "ndt-pause" }).catch(() => {});
    if (settings.pauseSound) {
      errorSound.currentTime = 0;
      errorSound.play().catch(console.error);
    }
  }
  else if (settings.autoResume) chrome.runtime.sendMessage({ type: "ndt-resume" }).catch(() => {});
}

function handleResult(result) {
  const now = performance.now();
  if (result.calibrating) {
    publish({
      phase: "calibrating",
      progress: result.progress ?? 0,
      reason: result.face ? null : "Volto non rilevato",
      paused: videosPaused,
    });
    return;
  }

  const reason = result.face ? result.awayReason : "Volto assente";
  if (reason) {
    backSince = null;
    awaySince ??= now;
    if (now - awaySince >= settings.pauseDelay) setPaused(true);
  } else {
    awaySince = null;
    if (videosPaused) {
      backSince ??= now;
      if (now - backSince >= RESUME_AFTER_MS) setPaused(false);
    }
  }

  publish({
    phase: reason ? "away" : "watching",
    progress: 100,
    reason,
    paused: videosPaused,
    pitchDelta: result.pitchDelta ?? null,
  });
}

function applySettings(next = {}) {
  settings = {
    cameraId: next.cameraId ?? settings.cameraId,
    pauseDelay: Number(next.pauseDelay ?? settings.pauseDelay),
    autoResume: next.autoResume ?? settings.autoResume,
    pauseSound: next.pauseSound ?? settings.pauseSound,
  };
}

async function start(nextSettings) {
  applySettings(nextSettings);
  detector.stop();
  awaySince = null;
  backSince = null;
  try {
    await detector.start(settings.cameraId);
  } catch (error) {
    console.error(error);
    publish({ running: false, phase: "error", error: error.name === "ModelError" ? error.message : cameraErrorHelp(error), errorName: error.name }, true);
    return { ok: false, error: state.error, errorName: error.name };
  }
  publish({
    running: true,
    phase: "calibrating",
    progress: 0,
    reason: null,
    paused: false,
    error: null,
    camera: detector.camera?.label ?? null,
    cameraId: detector.camera?.deviceId ?? null,
  }, true);
  return { ok: true };
}

function stop() {
  detector.stop();
  setPaused(false);
  publish({ running: false, phase: "off", reason: null, paused: false }, true);
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.target !== "offscreen") return false;
  switch (message.type) {
    case "start":
      start(message.settings).then(sendResponse);
      return true;
    case "stop":
      stop();
      sendResponse({ ok: true });
      return false;
    case "recalibrate":
      detector.recalibrate();
      sendResponse({ ok: true });
      return false;
    case "settings":
      applySettings(message.settings);
      sendResponse({ ok: true });
      return false;
    case "get-state":
      sendResponse(state);
      return false;
    default:
      return false;
  }
});
