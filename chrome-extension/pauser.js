// Content script: mette in pausa e riprende i video della pagina su richiesta
// del monitor. Riprende solo i video che ha messo in pausa lui.
(() => {
  if (window.__ndtPauser) return;
  window.__ndtPauser = true;

  const pausedByUs = new Set();

  function pauseAll() {
    for (const video of document.querySelectorAll("video")) {
      if (!video.paused && !video.ended) {
        pausedByUs.add(video);
        video.pause();
      }
    }
  }

  function resumeAll() {
    for (const video of pausedByUs) {
      if (video.isConnected && video.paused) video.play().catch(() => {});
    }
    pausedByUs.clear();
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "ndt-pause") pauseAll();
    else if (message?.type === "ndt-resume") resumeAll();
  });
})();
