// Riconoscimento del volto e dello sguardo, condiviso tra il documento
// offscreen (modalità pausa, funziona a pagina chiusa) e la pagina del monitor
// (modalità richiamo).
import {
  FaceLandmarker,
  FilesetResolver,
} from "./vendor/vision_bundle.mjs";

// MediaPipe scrive nella console i suoi log interni (formato glog, es.
// "W1005 16:00:48 … face_landmarker_graph.cc"), che Chrome mostra come errori
// dell'estensione. Non sono problemi: li filtriamo.
const MEDIAPIPE_LOG = /^[IWE]\d{4} \d|XNNPACK|TensorFlow Lite|OpenGL error checking/;
for (const level of ["log", "info", "warn", "error"]) {
  const original = console[level].bind(console);
  console[level] = (...args) => {
    if (typeof args[0] === "string" && MEDIAPIPE_LOG.test(args[0])) return;
    original(...args);
  };
}

// Webcam virtuali (OBS ecc.) che in modalità automatica vengono scartate:
// quando il programma che le alimenta è chiuso mandano un’immagine fissa.
export const VIRTUAL_CAMERA = /obs|virtual|snap camera|mmhmm|manycam|xsplit|ndi|droidcam|iriun/i;

const CALIBRATION_SAMPLES = 45;
const ANALYSIS_INTERVAL_MS = 66;
// Con questi landmark il pitch relativo aumenta quando il mento scende.
const HEAD_DOWN_DELTA = 7.0;
// Soglie della modalità pausa: oltre questi valori lo sguardo è "altrove".
const PAUSE_PITCH_DOWN = 14;
const PAUSE_PITCH_UP = -14;
const PAUSE_YAW_DELTA = 0.13;
const EYES_CLOSED = 0.55;
const EYES_LOOK_AWAY = 0.62;

let landmarkerPromise = null;

function loadLandmarker() {
  landmarkerPromise ??= (async () => {
    const vision = await FilesetResolver.forVisionTasks(
      chrome.runtime.getURL("vendor/wasm"),
    );
    const options = {
      baseOptions: {
        modelAssetPath: chrome.runtime.getURL("models/face_landmarker.task"),
        delegate: "GPU",
      },
      runningMode: "VIDEO",
      numFaces: 1,
      outputFaceBlendshapes: true,
      minFaceDetectionConfidence: 0.45,
      minFacePresenceConfidence: 0.45,
      minTrackingConfidence: 0.45,
    };
    try {
      return await FaceLandmarker.createFromOptions(vision, options);
    } catch (gpuError) {
      console.warn("GPU non disponibile, uso CPU.", gpuError);
      options.baseOptions.delegate = "CPU";
      return FaceLandmarker.createFromOptions(vision, options);
    }
  })();
  landmarkerPromise.catch(() => {
    landmarkerPromise = null;
  });
  return landmarkerPromise;
}

export async function listCameras() {
  const devices = await navigator.mediaDevices.enumerateDevices();
  return devices
    .filter((device) => device.kind === "videoinput" && device.deviceId)
    .map(({ deviceId, label }) => ({ deviceId, label }));
}

function openCamera(deviceId) {
  return navigator.mediaDevices.getUserMedia({
    audio: false,
    video: {
      width: { ideal: 1280 },
      height: { ideal: 720 },
      ...(deviceId ? { deviceId: { exact: deviceId } } : { facingMode: "user" }),
    },
  });
}

// Apre la webcam scelta; con cameraId vuoto preferisce una webcam fisica.
export async function openPreferredCamera(cameraId) {
  let stream;
  try {
    stream = await openCamera(cameraId);
  } catch (error) {
    if (!cameraId || error.name !== "OverconstrainedError") throw error;
    stream = await openCamera("");
  }

  // Solo dopo il permesso le etichette delle webcam sono leggibili.
  const cameras = await listCameras();
  const activeId = () => stream.getVideoTracks()[0]?.getSettings().deviceId;

  if (!cameraId || !cameras.some((camera) => camera.deviceId === cameraId)) {
    const current = cameras.find((camera) => camera.deviceId === activeId());
    const physical = cameras.find((camera) => !VIRTUAL_CAMERA.test(camera.label));
    if (physical && (!current || VIRTUAL_CAMERA.test(current.label))) {
      for (const track of stream.getTracks()) track.stop();
      stream = await openCamera(physical.deviceId);
    }
  }

  const active = cameras.find((camera) => camera.deviceId === activeId());
  return { stream, cameras, camera: active ?? null };
}

export function cameraErrorHelp(error) {
  const systemDenied = /system/i.test(error.message ?? "");
  switch (error.name) {
    case "NotAllowedError":
      return systemDenied
        ? "macOS blocca la webcam per Chrome.\nApri Impostazioni di Sistema › Privacy e sicurezza › Fotocamera, attiva Google Chrome, poi chiudi e riapri Chrome."
        : "Chrome non ha ancora il permesso di usare la webcam per questa estensione.\nApri il monitor, premi «Avvia» e scegli «Consenti». Se non compare nessuna richiesta, apri chrome://settings/content/camera e rimuovi l’estensione dai siti bloccati.";
    case "NotFoundError":
    case "OverconstrainedError":
      return "Nessuna webcam trovata. Controlla che sia collegata.";
    case "NotReadableError":
    case "AbortError":
      return "La webcam è occupata o bloccata dal sistema. Chiudi app che la usano (FaceTime, Zoom, Teams, Photo Booth…) e riprova.";
    default:
      return `Errore: ${error.name ?? "sconosciuto"}${error.message ? ` — ${error.message}` : ""}`;
  }
}

function median(values) {
  const sorted = [...values].sort((first, second) => first - second);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

function estimatePitch(landmarks) {
  const forehead = landmarks[10];
  const chin = landmarks[152];
  const vertical = Math.max(0.0001, chin.y - forehead.y);
  return Math.atan2(chin.z - forehead.z, vertical) * (180 / Math.PI);
}

function estimateYaw(landmarks) {
  const nose = landmarks[1];
  const left = landmarks[234];
  const right = landmarks[454];
  return (nose.x - left.x) / Math.max(0.0001, right.x - left.x);
}

function blendshapeScores(result) {
  const scores = {};
  for (const category of result.faceBlendshapes?.[0]?.categories ?? []) {
    scores[category.categoryName] = category.score;
  }
  return scores;
}

// Restituisce il motivo per cui lo sguardo non è sullo schermo, oppure null.
function lookAwayReason(pitchDelta, yawDelta, scores) {
  const both = (first, second) => Math.min(scores[first] ?? 0, scores[second] ?? 0);
  if (Math.abs(yawDelta) > PAUSE_YAW_DELTA) return "Testa girata";
  if (pitchDelta > PAUSE_PITCH_DOWN) return "Testa abbassata";
  if (pitchDelta < PAUSE_PITCH_UP) return "Testa alzata";
  if (both("eyeBlinkLeft", "eyeBlinkRight") > EYES_CLOSED) return "Occhi chiusi";
  if (both("eyeLookDownLeft", "eyeLookDownRight") > EYES_LOOK_AWAY) return "Sguardo in basso";
  if (both("eyeLookOutLeft", "eyeLookInRight") > EYES_LOOK_AWAY) return "Sguardo di lato";
  if (both("eyeLookInLeft", "eyeLookOutRight") > EYES_LOOK_AWAY) return "Sguardo di lato";
  return null;
}

// onResult riceve, a ogni fotogramma analizzato, uno di questi oggetti:
//   { face: false }
//   { face: true, calibrating: true, progress }
//   { face: true, calibrating: false, pitchDelta, awayReason, headDown }
export class Detector {
  constructor(onResult) {
    this.onResult = onResult;
    this.video = document.createElement("video");
    this.video.muted = true;
    this.video.playsInline = true;
    this.stream = null;
    this.imageCapture = null;
    this.camera = null;
    this.cameras = [];
    this.landmarker = null;
    this.busy = false;
    this.running = false;
    this.lastVideoTime = -1;
    // I timer dei worker non vengono rallentati in background.
    this.ticker = new Worker(new URL("./ticker.js", import.meta.url));
    this.ticker.onmessage = () => this.tick();
    this.recalibrate();
  }

  async start(cameraId) {
    // La webcam viene chiesta per prima, così un errore del modello non viene
    // scambiato per un problema della fotocamera.
    const { stream, cameras, camera } = await openPreferredCamera(cameraId);
    this.stream = stream;
    this.cameras = cameras;
    this.camera = camera;
    this.video.srcObject = stream;
    await this.video.play();
    const [track] = stream.getVideoTracks();
    // ImageCapture fornisce fotogrammi anche quando la pagina non è visibile.
    this.imageCapture = "ImageCapture" in self ? new ImageCapture(track) : null;

    try {
      this.landmarker = await loadLandmarker();
    } catch (error) {
      this.stop();
      throw Object.assign(new Error(`Il modello di riconoscimento non si è caricato: ${error.message ?? error}`), { name: "ModelError" });
    }

    this.recalibrate();
    this.running = true;
    this.ticker.postMessage(ANALYSIS_INTERVAL_MS);
  }

  stop() {
    this.running = false;
    this.ticker.postMessage(0);
    for (const track of this.stream?.getTracks() ?? []) track.stop();
    this.stream = null;
    this.imageCapture = null;
    this.video.srcObject = null;
  }

  recalibrate() {
    this.pitchSamples = [];
    this.yawSamples = [];
    this.pitchBaseline = null;
    this.yawBaseline = null;
    this.filteredPitch = null;
  }

  async grabFrame() {
    if (this.imageCapture) {
      try {
        return await this.imageCapture.grabFrame();
      } catch {
        // Ricade sull’elemento video.
      }
    }
    if (this.video.readyState < 2) return null;
    if (this.video.currentTime === this.lastVideoTime) return null;
    this.lastVideoTime = this.video.currentTime;
    return this.video;
  }

  async tick() {
    if (this.busy || !this.running) return;
    this.busy = true;
    try {
      const frame = await this.grabFrame();
      if (frame && this.running) this.analyze(frame);
      if (frame instanceof ImageBitmap) frame.close();
    } catch (error) {
      console.error(error);
    } finally {
      this.busy = false;
    }
  }

  analyze(frame) {
    const result = this.landmarker.detectForVideo(frame, performance.now());
    const landmarks = result.faceLandmarks?.[0];
    if (!landmarks) {
      this.onResult({ face: false, calibrating: this.pitchBaseline === null });
      return;
    }

    const rawPitch = estimatePitch(landmarks);
    const yaw = estimateYaw(landmarks);
    this.filteredPitch = this.filteredPitch === null
      ? rawPitch
      : 0.20 * rawPitch + 0.80 * this.filteredPitch;

    if (this.pitchBaseline === null) {
      this.pitchSamples.push(this.filteredPitch);
      this.yawSamples.push(yaw);
      const progress = Math.min(
        100,
        Math.round((this.pitchSamples.length / CALIBRATION_SAMPLES) * 100),
      );
      if (this.pitchSamples.length >= CALIBRATION_SAMPLES) {
        this.pitchBaseline = median(this.pitchSamples);
        this.yawBaseline = median(this.yawSamples);
      }
      this.onResult({ face: true, calibrating: true, progress });
      return;
    }

    const pitchDelta = this.filteredPitch - this.pitchBaseline;
    this.onResult({
      face: true,
      calibrating: false,
      pitchDelta,
      headDown: pitchDelta >= HEAD_DOWN_DELTA,
      awayReason: lookAwayReason(pitchDelta, yaw - this.yawBaseline, blendshapeScores(result)),
    });
  }
}
