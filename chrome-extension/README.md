<img src="icons/icon-128.png" width="96" height="96" align="right" alt="">

# 🧩 No Distraction Tool — Estensione Chrome

> Parte della repo [No Distraction Tool](../README.md), che contiene anche l'[app per Mac](../macos/), che mette in pausa qualsiasi programma.

Estensione Manifest V3 (Chrome 116+). Tutta l'analisi avviene in locale con MediaPipe Tasks Vision (WebAssembly incluso in `vendor/`).

## ⚙️ Come è fatta

```
popup / monitor ──ndt-start──▶ background.js (service worker)
                                   │ crea
                                   ▼
                              offscreen.html + offscreen.js
                                   │ usa detector.js (webcam + MediaPipe)
                                   │
                    ndt-pause / ndt-resume / ndt-state
                                   ▼
                           background.js ──▶ pauser.js in ogni scheda
```

| File | Ruolo |
| --- | --- |
| `background.js` | Service worker: crea/chiude il documento offscreen, inoltra pausa e ripresa alle schede, aggiorna il badge, avvio automatico all'apertura di Chrome |
| `offscreen.html/js` | Pagina invisibile che tiene accesa la webcam e decide quando mettere in pausa. Continua a funzionare senza schede dell'estensione aperte |
| `detector.js` | Webcam (scarta le webcam virtuali tipo OBS), calibrazione, stima di pitch/yaw, blendshape degli occhi |
| `ticker.js` | Web Worker che scandisce l'analisi: i suoi timer non vengono rallentati in background |
| `pauser.js` | Content script: mette in pausa i `<video>` in riproduzione e riprende solo quelli fermati da lui |
| `monitor.html/js` | Pannello con anteprima, scelta webcam e impostazioni; ospita anche le modalità scherzo |
| `popup.html/js` | Stato e pulsante Avvia/Interrompi |
| `sounds/error.mp3` | Segnale suonato dal documento offscreen quando scatta la pausa (casella «Suono di errore» nel monitor) |

Il permesso della webcam si può chiedere solo da una pagina visibile: per questo la prima volta si avvia dal monitor. Poi il documento offscreen riusa il permesso concesso all'estensione.

## 🎭 Modalità scherzo

Oltre alla pausa, il monitor ha le modalità originali (Enrico Papi, Serena Brancale, Ultimo, Benzina, Teams, Physical, Versione auto) che mostrano un richiamo quando abbassi la testa. Funzionano solo con la scheda del monitor aperta e richiedono i file in `media/`, che **non sono nella repo** (sono clip di terzi). Senza quei file il monitor mostra solo «Metti in pausa i video» e «Versione auto»: ogni modalità scherzo compare da sola appena trova tutti i suoi file in `chrome-extension/media/`.

La "Versione auto" è un prototipo dimostrativo non certificato: non usarla come sistema di sicurezza alla guida.

## ⚠️ Limiti

- Controlla solo i video dentro Chrome (non app native come Netflix per Mac, Spotify, VLC).
- I lettori che non usano un elemento `<video>` standard potrebbero non essere fermati.
- Le soglie dello sguardo sono in `detector.js` (`PAUSE_*`, `EYES_*`) e potrebbero richiedere taratura.

## 🧪 Test

Il flusso completo è stato verificato su Chrome 154 in headless, con una webcam finta (`--use-file-for-fake-video-capture`) che alterna volto presente e assente: calibrazione, pausa dopo il ritardo, ripresa al ritorno del volto, tutto senza pagine dell'estensione aperte.
