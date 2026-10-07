# No Distraction Tool

Mette in pausa i video quando smetti di guardare lo schermo e li fa ripartire quando torni a guardare.

La webcam viene analizzata **solo sul computer** con [MediaPipe Face Landmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker): nessun fotogramma viene salvato o inviato a un server.

## Cosa c'è nella repo

| Cartella | Contenuto |
| --- | --- |
| [`chrome-extension/`](chrome-extension/) | Estensione Chrome (Manifest V3): pausa automatica dei video in tutte le schede, anche a pagina chiusa |
| [`macos/`](macos/) | App per la barra dei menu di macOS: mette in pausa qualsiasi programma (Spotify, QuickTime, VLC, Safari, Chrome…) |

## Quando considera che "non stai guardando"

- volto assente dall'inquadratura;
- testa girata, abbassata o alzata rispetto alla posizione calibrata;
- occhi chiusi;
- sguardo di lato o in basso (per esempio verso il telefono).

Dopo il ritardo scelto (0,7 – 5 secondi) mette in pausa e suona un breve segnale di errore (disattivabile dal monitor); quando torni a guardare riprende solo i video che aveva fermato.

## Installare l'estensione

1. Apri `chrome://extensions` e attiva **Modalità sviluppatore**.
2. **Carica estensione non pacchettizzata** → scegli la cartella `chrome-extension`.
3. Clicca l'icona dell'estensione → **Apri il monitor** → **Avvia monitoraggio** e consenti la webcam (serve solo la prima volta).
4. Guarda dritto qualche secondo per la calibrazione. Da qui puoi chiudere la scheda: l'analisi continua in background.

Dopo il primo permesso puoi avviare e fermare tutto dal pulsante nel popup dell'icona. L'icona mostra lo stato: `…` calibrazione, `ON` attivo, `II` video in pausa.

Dettagli tecnici in [`chrome-extension/README.md`](chrome-extension/README.md).
