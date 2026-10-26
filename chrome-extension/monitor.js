import {
  Detector,
  VIRTUAL_CAMERA,
  cameraErrorHelp,
  listCameras,
  openPreferredCamera,
} from "./detector.js";

// "pause" gira nel documento offscreen e continua a pagina chiusa; le altre
// modalità mostrano un richiamo in questa pagina, che deve restare aperta.
const MODES = {
  pause: {
    label: "Metti in pausa i video",
    type: "pause",
  },
  enrico: {
    label: "Enrico Papi",
    type: "video",
    video: "media/video4.mp4",
    audio: "media/audio4.mp3",
  },
  serena: {
    label: "Serena Brancale",
    type: "video",
    video: "media/brancale.mp4",
    audio: "media/brancale.mp3",
  },
  ultimo: {
    label: "Ultimo",
    type: "video",
    video: "media/ultimo2.mp4",
    audio: "media/ultimo2.mp3",
  },
  benzina: {
    label: "Benzina",
    type: "slideshow",
    audio: "media/songsus.mp3",
    images: [
      "media/benz/benz1.jpeg",
      "media/benz/benz2.jpeg",
      "media/benz/benz3.jpeg",
      "media/benz/benz4.jpeg",
    ],
  },
  automotive: {
    label: "Versione auto",
    type: "automotive",
  },
  teams: {
    label: "Teams",
    type: "video",
    video: "media/teams.mp4",
    audio: "media/teams.mp3",
  },
  physical: {
    label: "Physical",
    type: "video",
    video: "media/physical.mp4",
    audio: "media/physical.mp3",
  },
};

const DOWN_ON_FRAMES = 7;
const FORWARD_OFF_FRAMES = 10;
const SLIDE_DURATION_MS = 2000;
const GREEN = "#58e7b3";
const AMBER = "#ffbf47";
const RED = "#ff4964";

const $ = (selector) => document.querySelector(selector);
const elements = {
  preview: $("#preview"),
  cameraSelect: $("#camera-select"),
  modeSelect: $("#mode-select"),
  pauseOptions: $("#pause-options"),
  delaySelect: $("#delay-select"),
  resumeCheck: $("#resume-check"),
  soundCheck: $("#sound-check"),
  autostartCheck: $("#autostart-check"),
  intro: $("#intro"),
  startButton: $("#start-button"),
  stopButton: $("#stop-button"),
  calibrateButton: $("#calibrate-button"),
  systemStatus: $("#system-status"),
  gazeStatus: $("#gaze-status"),
  calibrationStatus: $("#calibration-status"),
  cameraStatus: $("#camera-status"),
  pitchStatus: $("#pitch-status"),
  privacyBadge: $("#privacy-badge"),
  backgroundNote: $("#background-note"),
  errorHelp: $("#error-help"),
  alertOverlay: $("#alert-overlay"),
  standardAlert: $("#standard-alert"),
  alertVideo: $("#alert-video"),
  slideshowAlert: $("#slideshow-alert"),
  slideshowImage: $("#slideshow-image"),
  automotiveAlert: $("#automotive-alert"),
  alertAudio: $("#alert-audio"),
  dismissAlert: $("#dismiss-alert"),
};

const previewContext = elements.preview.getContext("2d", { alpha: false });
const previewVideo = document.createElement("video");
previewVideo.muted = true;
previewVideo.playsInline = true;

// running: null (fermo), "background" (offscreen) oppure "page" (richiamo).
let running = null;
let previewStream = null;
let overlay = { text: "PREMI AVVIA MONITORAGGIO", color: "#93a0b3" };
let pageDetector = null;
let downFrames = 0;
let forwardFrames = 0;
let alertActive = false;
let dismissedUntilForward = false;
let slideshowTimer = null;
let slideshowOrder = [];
let slideshowIndex = 0;
let audioContext = null;
let alertGain = null;
let automotiveTimer = null;

// ---------- Impostazioni ----------

function currentMode() {
  return MODES[elements.modeSelect.value];
}

// I file in media/ non sono nella repo: una modalità compare solo se ci sono
// tutti i suoi file, così chi installa dalla repo vede pausa e versione auto.
function modeFiles(mode) {
  return [mode.video, mode.audio, ...(mode.images ?? [])].filter(Boolean);
}

async function fileExists(path) {
  try {
    const response = await fetch(extensionUrl(path));
    response.body?.cancel();
    return response.ok;
  } catch {
    return false;
  }
}

async function populateModes() {
  for (const [key, mode] of Object.entries(MODES)) {
    const files = await Promise.all(modeFiles(mode).map(fileExists));
    if (files.every(Boolean)) elements.modeSelect.append(new Option(mode.label, key));
  }
}

function populateCameraSelect(cameras, selectedId) {
  const select = elements.cameraSelect;
  select.replaceChildren(new Option("Automatica (esclude webcam virtuali)", ""));
  cameras.forEach((camera, index) => {
    const name = camera.label || `Webcam ${index + 1}`;
    const suffix = VIRTUAL_CAMERA.test(name) ? " — virtuale" : "";
    select.append(new Option(name + suffix, camera.deviceId));
  });
  select.value = cameras.some((camera) => camera.deviceId === selectedId) ? selectedId : "";
}

function updateModeUi() {
  const pauseMode = currentMode().type === "pause";
  elements.pauseOptions.hidden = !pauseMode;
  elements.intro.textContent = pauseMode
    ? "Quando smetti di guardare lo schermo i video vengono messi in pausa e ripartono quando torni a guardare."
    : "Scegli il richiamo da mostrare quando il sistema rileva la testa abbassata. Questa scheda deve restare aperta.";
}

async function restoreSettings() {
  const settings = await chrome.storage.local.get({
    selectedModeV2: "pause",
    pauseDelay: "1500",
    autoResume: true,
    pauseSound: true,
    autoStart: false,
    cameraId: "",
  });
  if (MODES[settings.selectedModeV2]) elements.modeSelect.value = settings.selectedModeV2;
  elements.delaySelect.value = settings.pauseDelay;
  elements.resumeCheck.checked = settings.autoResume;
  elements.soundCheck.checked = settings.pauseSound;
  elements.autostartCheck.checked = settings.autoStart;
  populateCameraSelect(await listCameras().catch(() => []), settings.cameraId);
  updateModeUi();
}

function saveSettings() {
  return chrome.storage.local.set({
    selectedModeV2: elements.modeSelect.value,
    pauseDelay: elements.delaySelect.value,
    autoResume: elements.resumeCheck.checked,
    pauseSound: elements.soundCheck.checked,
    autoStart: elements.autostartCheck.checked,
    cameraId: elements.cameraSelect.value,
  });
}

// ---------- Interfaccia ----------

function setSystemStatus(message) {
  elements.systemStatus.textContent = message;
}

function showError(message) {
  elements.errorHelp.textContent = message ?? "";
  elements.errorHelp.hidden = !message;
}

function setControls(mode) {
  running = mode;
  const active = Boolean(mode);
  elements.startButton.disabled = active;
  elements.stopButton.disabled = !active;
  elements.calibrateButton.disabled = !active;
  elements.modeSelect.disabled = active;
  elements.backgroundNote.hidden = mode !== "background";
  elements.privacyBadge.classList.toggle("active", active);
  elements.privacyBadge.textContent = active
    ? "● CAMERA ATTIVA — ELABORAZIONE LOCALE"
    : "● CAMERA DISATTIVATA";
  if (!active) {
    setSystemStatus("Non attivo");
    elements.gazeStatus.textContent = "—";
    elements.calibrationStatus.textContent = "—";
    elements.cameraStatus.textContent = "In attesa di avvio";
    elements.pitchStatus.textContent = "Pitch: —";
    overlay = { text: "PREMI AVVIA MONITORAGGIO", color: "#93a0b3" };
  }
}

function showCalibration(progress, faceFound) {
  elements.calibrationStatus.textContent = `${progress}%`;
  elements.gazeStatus.textContent = "—";
  setSystemStatus("Calibrazione…");
  elements.cameraStatus.textContent = faceFound ? "Guarda dritto per calibrare" : "Volto non rilevato";
  overlay = faceFound
    ? { text: `CALIBRAZIONE ${progress}%`, color: AMBER }
    : { text: "VOLTO NON RILEVATO", color: AMBER };
}

function drawPreview() {
  requestAnimationFrame(drawPreview);
  if (document.hidden) return;
  const { width, height } = elements.preview;
  if (previewVideo.readyState >= 2) {
    previewContext.save();
    previewContext.translate(width, 0);
    previewContext.scale(-1, 1);
    previewContext.drawImage(previewVideo, 0, 0, width, height);
    previewContext.restore();
  } else {
    previewContext.fillStyle = "#05070a";
    previewContext.fillRect(0, 0, width, height);
  }

  const gradient = previewContext.createLinearGradient(0, 0, 0, height * 0.3);
  gradient.addColorStop(0, "rgba(0, 0, 0, 0.6)");
  gradient.addColorStop(1, "transparent");
  previewContext.fillStyle = gradient;
  previewContext.fillRect(0, 0, width, height);

  // In alto: in basso ci sono già le etichette di stato e il bordo può
  // essere tagliato da object-fit: cover.
  const fontSize = Math.max(18, Math.round(width / 42));
  previewContext.fillStyle = overlay.color;
  previewContext.font = `800 ${fontSize}px -apple-system, "Segoe UI", sans-serif`;
  previewContext.fillText(overlay.text, Math.round(width * 0.05), Math.round(height * 0.06) + fontSize);
}

async function startPreview(cameraId) {
  stopPreview();
  const { stream, cameras, camera } = await openPreferredCamera(cameraId);
  previewStream = stream;
  previewVideo.srcObject = stream;
  await previewVideo.play();
  elements.preview.width = previewVideo.videoWidth || 1280;
  elements.preview.height = previewVideo.videoHeight || 720;
  populateCameraSelect(cameras, elements.cameraSelect.value);
  return camera;
}

function stopPreview() {
  for (const track of previewStream?.getTracks() ?? []) track.stop();
  previewStream = null;
  previewVideo.srcObject = null;
}

// ---------- Modalità pausa (documento offscreen) ----------

function applyBackgroundState(state) {
  if (!state?.running) {
    if (running === "background") {
      stopPreview();
      setControls(null);
    }
    if (state?.phase === "error" && state.error) showError(state.error);
    return;
  }

  if (running !== "background") {
    setControls("background");
    if (!previewStream) startPreview(state.cameraId).catch(console.error);
  }

  if (state.phase === "calibrating") {
    showCalibration(state.progress ?? 0, !state.reason);
    return;
  }

  const reason = state.reason;
  elements.calibrationStatus.textContent = "Completata";
  elements.gazeStatus.textContent = reason ?? "Sullo schermo";
  elements.cameraStatus.textContent = state.camera ?? "Monitoraggio attivo";
  if (typeof state.pitchDelta === "number") {
    elements.pitchStatus.textContent = `Pitch relativo: ${state.pitchDelta.toFixed(1)}°`;
  }
  if (state.paused) {
    setSystemStatus("Video in pausa");
  } else {
    setSystemStatus(reason ? "Non stai guardando…" : "Stai guardando");
  }
  overlay = reason
    ? { text: (state.paused ? `${reason} — PAUSA` : reason).toUpperCase(), color: RED }
    : { text: "STAI GUARDANDO", color: GREEN };
}

async function startBackground() {
  // Il permesso della webcam si può chiedere solo da una pagina visibile:
  // la si apre qui (serve anche per l’anteprima), poi parte l’analisi.
  setSystemStatus("Accesso alla webcam…");
  await startPreview(elements.cameraSelect.value);
  setSystemStatus("Avvio analisi…");
  const result = await chrome.runtime.sendMessage({ type: "ndt-start" });
  if (!result?.ok) {
    stopPreview();
    throw Object.assign(new Error(result?.error ?? "Avvio non riuscito"), {
      name: result?.errorName ?? "StartError",
      help: result?.error,
    });
  }
  setControls("background");
  showCalibration(0, true);
}

// ---------- Modalità richiamo (in questa pagina) ----------

function handlePageResult(result) {
  if (result.calibrating || !result.face) {
    if (result.calibrating) showCalibration(result.progress ?? 0, result.face);
    else {
      elements.cameraStatus.textContent = "Volto non rilevato";
      overlay = { text: "VOLTO NON RILEVATO", color: AMBER };
    }
    return;
  }

  elements.calibrationStatus.textContent = "Completata";
  elements.pitchStatus.textContent = `Pitch relativo: ${result.pitchDelta.toFixed(1)}°`;
  if (result.headDown) {
    downFrames += 1;
    forwardFrames = 0;
    elements.gazeStatus.textContent = "Testa abbassata";
    setSystemStatus("Distrazione rilevata");
    overlay = { text: "TESTA ABBASSATA", color: RED };
  } else {
    forwardFrames += 1;
    downFrames = 0;
    elements.gazeStatus.textContent = "Posizione corretta";
    setSystemStatus("Posizione corretta");
    overlay = { text: "POSIZIONE CORRETTA", color: GREEN };
  }

  if (!alertActive && !dismissedUntilForward && downFrames >= DOWN_ON_FRAMES) startAlert();
  if (forwardFrames >= FORWARD_OFF_FRAMES) {
    dismissedUntilForward = false;
    if (alertActive) stopAlert();
  }
}

async function startPage() {
  await unlockAudio();
  pageDetector ??= new Detector(handlePageResult);
  setSystemStatus("Accesso alla webcam…");
  await pageDetector.start(elements.cameraSelect.value);
  previewStream = null;
  previewVideo.srcObject = pageDetector.stream;
  await previewVideo.play();
  elements.preview.width = previewVideo.videoWidth || 1280;
  elements.preview.height = previewVideo.videoHeight || 720;
  populateCameraSelect(pageDetector.cameras, elements.cameraSelect.value);
  elements.cameraStatus.textContent = pageDetector.camera?.label ?? "Monitoraggio attivo";
  downFrames = 0;
  forwardFrames = 0;
  setControls("page");
  showCalibration(0, true);
}

// ---------- Avvio / arresto ----------

async function startMonitoring() {
  if (running) return;
  elements.startButton.disabled = true;
  showError("");
  await saveSettings();
  try {
    if (currentMode().type === "pause") await startBackground();
    else await startPage();
  } catch (error) {
    console.error(error);
    stopPreview();
    pageDetector?.stop();
    setControls(null);
    setSystemStatus("Avvio non riuscito");
    showError(error.help ?? (error.name === "ModelError" ? error.message : cameraErrorHelp(error)));
  }
}

async function stopMonitoring() {
  if (running === "background") await chrome.runtime.sendMessage({ type: "ndt-stop" });
  pageDetector?.stop();
  stopAlert();
  stopPreview();
  setControls(null);
}

function recalibrate() {
  if (running === "background") chrome.runtime.sendMessage({ type: "ndt-recalibrate" });
  else pageDetector?.recalibrate();
  dismissedUntilForward = false;
  stopAlert();
  showCalibration(0, true);
}

async function changeCamera() {
  await saveSettings();
  if (running === "background") {
    // Il service worker riavvia l’analisi con la nuova webcam.
    await startPreview(elements.cameraSelect.value).catch(console.error);
  } else if (running === "page") {
    await stopMonitoring();
    await startMonitoring();
  }
}

// ---------- Richiami visivi e sonori ----------

function extensionUrl(path) {
  return chrome.runtime.getURL(path);
}

function shuffle(values) {
  const shuffled = [...values];
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const replacement = Math.floor(Math.random() * (index + 1));
    [shuffled[index], shuffled[replacement]] = [shuffled[replacement], shuffled[index]];
  }
  return shuffled;
}

async function unlockAudio() {
  audioContext ??= new AudioContext();
  await audioContext.resume();
  alertGain ??= audioContext.createGain();
  alertGain.gain.value = 0;
  alertGain.connect(audioContext.destination);
}

function restartSlideAnimation() {
  elements.slideshowImage.classList.remove("zooming");
  void elements.slideshowImage.offsetWidth;
  elements.slideshowImage.classList.add("zooming");
}

function showNextSlide() {
  if (!slideshowOrder.length) return;
  if (slideshowIndex >= slideshowOrder.length) {
    slideshowOrder = shuffle(slideshowOrder);
    slideshowIndex = 0;
  }
  elements.slideshowImage.src = extensionUrl(slideshowOrder[slideshowIndex]);
  slideshowIndex += 1;
  restartSlideAnimation();
}

function playAutomotiveBurst() {
  if (!audioContext || !alertGain) return;
  const start = audioContext.currentTime;
  alertGain.gain.cancelScheduledValues(start);
  alertGain.gain.setValueAtTime(0.68, start);

  const oscillator = audioContext.createOscillator();
  oscillator.type = "square";
  oscillator.frequency.setValueAtTime(980, start);
  oscillator.frequency.setValueAtTime(1380, start + 0.22);
  oscillator.frequency.setValueAtTime(980, start + 0.44);
  oscillator.connect(alertGain);
  oscillator.start(start);
  oscillator.stop(start + 0.64);
}

function startAutomotiveSound() {
  alertGain.gain.value = 0.68;
  playAutomotiveBurst();
  automotiveTimer = window.setInterval(playAutomotiveBurst, 760);
}

function stopAutomotiveSound() {
  window.clearInterval(automotiveTimer);
  automotiveTimer = null;
  if (alertGain) alertGain.gain.value = 0;
}

async function startAlert() {
  const mode = currentMode();
  alertActive = true;
  elements.alertOverlay.hidden = false;

  if (mode.type === "video") {
    elements.standardAlert.hidden = false;
    elements.alertVideo.src = extensionUrl(mode.video);
    elements.alertAudio.src = extensionUrl(mode.audio);
    elements.alertVideo.currentTime = 0;
    elements.alertAudio.currentTime = 0;
    await Promise.allSettled([elements.alertVideo.play(), elements.alertAudio.play()]);
  } else if (mode.type === "slideshow") {
    elements.slideshowAlert.hidden = false;
    slideshowOrder = shuffle(mode.images);
    slideshowIndex = 0;
    showNextSlide();
    slideshowTimer = window.setInterval(showNextSlide, SLIDE_DURATION_MS);
    elements.alertAudio.src = extensionUrl(mode.audio);
    elements.alertAudio.currentTime = 0;
    await elements.alertAudio.play().catch(console.error);
  } else {
    elements.automotiveAlert.hidden = false;
    startAutomotiveSound();
  }
}

function stopAlert() {
  alertActive = false;
  elements.alertOverlay.hidden = true;
  elements.standardAlert.hidden = true;
  elements.slideshowAlert.hidden = true;
  elements.automotiveAlert.hidden = true;

  elements.alertVideo.pause();
  elements.alertVideo.removeAttribute("src");
  elements.alertVideo.load();
  elements.alertAudio.pause();
  elements.alertAudio.removeAttribute("src");
  elements.alertAudio.load();

  window.clearInterval(slideshowTimer);
  slideshowTimer = null;
  slideshowOrder = [];
  slideshowIndex = 0;
  stopAutomotiveSound();
}

// ---------- Collegamenti ----------

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "ndt-state") applyBackgroundState(message.state);
  return false;
});

elements.modeSelect.addEventListener("change", () => {
  updateModeUi();
  saveSettings();
});
elements.cameraSelect.addEventListener("change", changeCamera);
elements.delaySelect.addEventListener("change", saveSettings);
elements.resumeCheck.addEventListener("change", saveSettings);
elements.soundCheck.addEventListener("change", saveSettings);
elements.autostartCheck.addEventListener("change", saveSettings);
elements.startButton.addEventListener("click", startMonitoring);
elements.stopButton.addEventListener("click", stopMonitoring);
elements.calibrateButton.addEventListener("click", recalibrate);
elements.dismissAlert.addEventListener("click", () => {
  dismissedUntilForward = true;
  stopAlert();
});
// Chiudere la pagina ferma solo la modalità richiamo: la pausa continua.
window.addEventListener("pagehide", () => {
  pageDetector?.stop();
  stopPreview();
});

await populateModes();
drawPreview();
await restoreSettings();
applyBackgroundState(await chrome.runtime.sendMessage({ type: "ndt-get-state" }));
