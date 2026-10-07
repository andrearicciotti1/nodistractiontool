const statusLabel = document.querySelector("#status");
const detail = document.querySelector("#detail");
const toggle = document.querySelector("#toggle");
const openMonitorButton = document.querySelector("#open-monitor");

let running = false;

async function openMonitor() {
  await chrome.tabs.create({ url: chrome.runtime.getURL("monitor.html") });
  window.close();
}

function render(state) {
  running = Boolean(state?.running);
  toggle.disabled = false;
  toggle.textContent = running ? "Interrompi" : "Avvia";
  toggle.classList.toggle("secondary", running);

  let text = "Non attivo";
  let tone = "";
  let info = "Quando smetti di guardare lo schermo, i video vanno in pausa.";
  if (state?.phase === "error") {
    text = "Errore";
    tone = "error";
    info = state.error ?? "Avvio non riuscito.";
  } else if (running && state.phase === "calibrating") {
    text = `Calibrazione ${state.progress ?? 0}%`;
    tone = "away";
    info = "Guarda dritto verso lo schermo per qualche secondo.";
  } else if (running && state.paused) {
    text = "Video in pausa";
    tone = "paused";
    info = state.reason ?? "";
  } else if (running) {
    text = state.reason ? state.reason : "Stai guardando";
    tone = state.reason ? "away" : "on";
    info = "Puoi chiudere questo riquadro: l’analisi continua in background.";
  }
  statusLabel.textContent = text;
  statusLabel.className = `status ${tone}`;
  detail.textContent = info;
}

toggle.addEventListener("click", async () => {
  toggle.disabled = true;
  if (running) {
    render(await chrome.runtime.sendMessage({ type: "ndt-stop" }).then(() => null));
    return;
  }
  await chrome.storage.local.set({ selectedModeV2: "pause" });
  render({ running: true, phase: "calibrating", progress: 0 });
  const result = await chrome.runtime.sendMessage({ type: "ndt-start" });
  if (!result?.ok) {
    // Il primo permesso della webcam si può dare solo da una pagina visibile.
    if (result?.errorName === "NotAllowedError") {
      await openMonitor();
      return;
    }
    render({ running: false, phase: "error", error: result?.error });
  }
});

openMonitorButton.addEventListener("click", openMonitor);

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "ndt-state") render(message.state);
  return false;
});

chrome.runtime.sendMessage({ type: "ndt-get-state" }).then(render);
