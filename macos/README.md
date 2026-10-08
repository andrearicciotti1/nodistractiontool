<img src="../branding/icon-256.png" width="96" height="96" align="right" alt="">

# 🖥️ No Distraction — app per la barra dei menu di macOS

> Parte della repo [No Distraction Tool](../README.md), che contiene anche l'[estensione Chrome](../chrome-extension/).

Stessa idea dell'estensione Chrome, ma per **qualsiasi programma**: Chrome, Safari, Spotify, Musica, QuickTime, VLC, IINA, Netflix e YouTube nel browser… Quando smetti di guardare lo schermo mette in pausa ciò che sta suonando, suona `error.mp3` e riprende quando torni a guardare.

Requisiti: macOS 13+ (consigliato 14.2+), Xcode o i Command Line Tools per compilare.

## ⬇️ Scaricare

Il DMG pronto è nelle [Release](https://github.com/andrearicciotti1/nodistractiontool/releases/latest).

## 📦 Compilare e installare

```bash
cd macos
./make-dmg.sh          # DMG di installazione: build/No-Distraction-<versione>.dmg
./build.sh --install   # oppure: compila e copia direttamente in /Applications
```

L'app è universale (Intel + Apple Silicon). `make-dmg.sh` usa [dmgbuild](https://github.com/dmgbuild/dmgbuild), installato da solo in `.build/dmg-venv` al primo uso, per impaginare la finestra (sfondo, freccia, icona del volume) senza pilotare Finder.

<p align="center"><img src="../branding/dmg-preview.jpg" width="520" alt="Finestra del DMG"></p>

## 🚀 Primo avvio

0. L'app non è firmata con un certificato Apple: la prima volta fai **clic destro › Apri** (oppure Impostazioni › Privacy e sicurezza › *Apri comunque*).
1. Apri **No Distraction** da Applicazioni: compare un'icona a forma di occhio nella barra dei menu.
2. Consenti l'accesso alla **webcam**.
3. Nel menu premi **Concedi permesso** e attiva No Distraction in *Impostazioni di Sistema › Privacy e sicurezza › Accessibilità*. Serve per premere il tasto ⏯ al posto tuo.
4. Guarda lo schermo per circa 3 secondi (calibrazione).

L'app è firmata "ad hoc": dopo ogni ricompilazione macOS può chiedere di nuovo i permessi. Se l'Accessibilità risulta attiva ma non funziona, rimuovila dall'elenco e aggiungila di nuovo.

## 🎨 Controllare la grafica

```bash
"build/No Distraction.app/Contents/MacOS/NoDistraction" --debug-snapshot /tmp/menu
```

Apre il pannello da solo e salva `/tmp/menu-1.png` e `/tmp/menu-2.png` (prima e dopo aver allungato il contenuto).

## ⚙️ Come funziona

| File | Ruolo |
| --- | --- |
| `GazeDetector.swift` | Apple Vision: rotazione della testa (yaw/pitch), apertura degli occhi, posizione delle pupille, confrontate con la calibrazione |
| `CameraService.swift` | Webcam a 10 fotogrammi al secondo; in automatico scarta quelle virtuali (OBS ecc.) |
| `MediaPauser.swift` | Pausa e ripresa di qualsiasi programma |
| `AppModel.swift` | Stato, impostazioni, ritardo prima della pausa, ripresa |
| `MenuView.swift` | Contenuto del menu: stato, anteprima della webcam, impostazioni |
| `StatusPanel.swift` | Icona nella barra e pannello del menu (AppKit: la finestra di `MenuBarExtra` su macOS recenti aggiunge un fondo trasparente in più e non si adatta al contenuto) |

### ⏯️ Pausa di qualsiasi programma

macOS 15.4+ non permette più alle app di terze parti di comandare la riproduzione con MediaRemote. L'app quindi simula il **tasto ⏯** della tastiera, che macOS consegna al programma in riproduzione.

Il tasto è un interruttore: premuto quando non suona niente farebbe *partire* l'ultimo video. Per evitarlo, l'app usa l'elenco dei processi che stanno riproducendo audio (CoreAudio, macOS 14.2+):

- preme ⏯ solo se qualche programma sta davvero suonando, escluse le app di chiamata (Zoom, Teams, FaceTime, Discord, Slack, WhatsApp, Telegram);
- dopo circa un secondo controlla che il programma si sia fermato; se invece è partito qualcos'altro, preme di nuovo ⏯ per tornare com'era;
- alla ripresa preme ⏯ solo se aveva messo in pausa qualcosa e nel frattempo non l'hai già fatto ripartire tu.

Limiti: i video **senza audio** (o muti) non vengono rilevati come "in riproduzione" e quindi non vengono fermati; i programmi che ignorano il tasto ⏯ non si fermano. Su macOS 13 – 14.1 l'elenco dei processi audio non esiste e la pausa non viene fatta.

**Non usare insieme all'estensione Chrome**: metterebbero in pausa entrambe.
