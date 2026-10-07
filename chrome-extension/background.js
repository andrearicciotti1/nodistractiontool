// Service worker: avvia e ferma il documento offscreen che analizza la webcam,
// inoltra pausa/ripresa alle schede e mostra lo stato sull’icona.
const OFFSCREEN_URL = "offscreen.html";
const DEFAULT_SETTINGS = {
  cameraId: "",
  pauseDelay: "1500",
  autoResume: true,
  pauseSound: true,
  autoStart: false,
};
const OFF_STATE = { running: false, phase: "off" };

let creatingOffscreen = null;

async function hasOffscreen() {
  const contexts = await chrome.runtime.getContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
  });
  return contexts.length > 0;
}

async function ensureOffscreen() {
  if (await hasOffscreen()) return;
  creatingOffscreen ??= chrome.offscreen.createDocument({
    url: OFFSCREEN_URL,
    reasons: ["USER_MEDIA"],
    justification: "Analizza la webcam in locale per mettere in pausa i video quando non guardi lo schermo.",
  }).finally(() => {
    creatingOffscreen = null;
  });
  await creatingOffscreen;
}

async function closeOffscreen() {
  if (await hasOffscreen()) await chrome.offscreen.closeDocument().catch(() => {});
}

function getSettings() {
  return chrome.storage.local.get(DEFAULT_SETTINGS);
}

function sendToOffscreen(type, extra = {}) {
  return chrome.runtime.sendMessage({ target: "offscreen", type, ...extra });
}

async function broadcast(type) {
  const tabs = await chrome.tabs.query({});
  await Promise.allSettled(
    tabs.map((tab) => chrome.tabs.sendMessage(tab.id, { type })),
  );
}

// Le schede aperte prima dell’installazione non hanno ancora il content script.
async function injectIntoOpenTabs() {
  const tabs = await chrome.tabs.query({ url: ["http://*/*", "https://*/*"] });
  await Promise.allSettled(
    tabs.map((tab) => chrome.scripting.executeScript({
      target: { tabId: tab.id, allFrames: true },
      files: ["pauser.js"],
    })),
  );
}

async function saveState(state) {
  await chrome.storage.session.set({ state });
  updateBadge(state);
}

function updateBadge(state) {
  let text = "";
  let color = "#58e7b3";
  if (state.running) {
    if (state.paused) {
      text = "II";
      color = "#ff4964";
    } else if (state.phase === "calibrating") {
      text = "…";
      color = "#ffbf47";
    } else {
      text = "ON";
      color = state.phase === "away" ? "#ffbf47" : "#58e7b3";
    }
  }
  chrome.action.setBadgeText({ text });
  chrome.action.setBadgeBackgroundColor({ color });
}

async function start() {
  await ensureOffscreen();
  await injectIntoOpenTabs();
  const result = await sendToOffscreen("start", { settings: await getSettings() })
    .catch((error) => ({ ok: false, error: String(error) }));
  if (!result?.ok) {
    await closeOffscreen();
    await saveState({ ...OFF_STATE, phase: "error", error: result?.error, errorName: result?.errorName });
  }
  return result;
}

async function stop() {
  if (await hasOffscreen()) {
    await sendToOffscreen("stop").catch(() => {});
    await closeOffscreen();
  }
  await saveState(OFF_STATE);
  return { ok: true };
}

async function currentState() {
  if (!(await hasOffscreen())) return OFF_STATE;
  const { state = OFF_STATE } = await chrome.storage.session.get("state");
  return state;
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message?.type) {
    case "ndt-start":
      start().then(sendResponse);
      return true;
    case "ndt-stop":
      stop().then(sendResponse);
      return true;
    case "ndt-recalibrate":
      sendToOffscreen("recalibrate").then(sendResponse, () => sendResponse({ ok: false }));
      return true;
    case "ndt-get-state":
      currentState().then(sendResponse);
      return true;
    case "ndt-state":
      saveState(message.state);
      return false;
    case "ndt-pause":
    case "ndt-resume":
      // Arriva dal documento offscreen, che non può usare chrome.tabs.
      if (sender.url?.endsWith(OFFSCREEN_URL)) broadcast(message.type);
      return false;
    default:
      return false;
  }
});

chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area !== "local" || !(await hasOffscreen())) return;
  if (changes.cameraId) {
    await start();
  } else if (changes.pauseDelay || changes.autoResume || changes.pauseSound) {
    sendToOffscreen("settings", { settings: await getSettings() }).catch(() => {});
  }
});

chrome.runtime.onStartup.addListener(async () => {
  await saveState(OFF_STATE);
  const { autoStart } = await getSettings();
  if (autoStart) start();
});

chrome.runtime.onInstalled.addListener(() => saveState(OFF_STATE));
