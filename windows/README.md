<img src="../branding/icon-256.png" width="96" height="96" align="right" alt="">

# 🪟 No Distraction per Windows

> Parte della repo [No Distraction Tool](../README.md), che contiene anche l'[app per Mac](../macos/) e l'[estensione Chrome](../chrome-extension/).

App per l'area di notifica di Windows (vicino all'orologio): quando smetti di guardare lo schermo mette in pausa **qualsiasi programma** che sta riproducendo, suona `error.wav` e riprende quando torni a guardare.

Requisiti: Windows 10 o 11 a 64 bit.

## ⬇️ Installare

1. Scarica **No-Distraction-Setup-&lt;versione&gt;.exe** dalle [Release](https://github.com/andrearicciotti1/nodistractiontool/releases/latest).
2. ⚠️ L'installer non è firmato con un certificato: Windows può mostrare *"Windows ha protetto il PC"*. Clicca **Ulteriori informazioni › Esegui comunque**.
3. Segui la procedura (non servono permessi di amministratore). Puoi scegliere l'avvio con Windows e l'icona sul desktop.
4. All'avvio guarda lo schermo per qualche secondo (calibrazione). L'app resta nell'area di notifica: clic sull'icona per aprire il pannello, tasto destro per il menu.

Se la webcam non parte: *Impostazioni › Privacy e sicurezza › Fotocamera* → attiva l'accesso alle app desktop.

## ✨ Cosa fa

Stesse funzioni dell'app per Mac: calibrazione, volto assente, testa girata o inclinata, occhi chiusi, sguardo di lato o in basso; ritardo da 0,3 a 30 secondi; ripresa automatica; suono di errore; scelta della webcam senza quelle virtuali; avvio con Windows. Il pallino sull'icona mostra lo stato: 🟢 stai guardando, 🟠 distratto o calibrazione, 🔴 in pausa.

### ⏯️ Pausa di qualsiasi programma

Usa i **controlli multimediali di sistema** di Windows (le stesse schede che compaiono vicino al volume). Per ogni programma sa se sta riproducendo e gli manda un comando esplicito di **Pausa** e poi di **Play**: niente tasto simulato, e riprende solo ciò che aveva fermato.

Funziona con Chrome, Edge, Firefox (YouTube, Netflix…), Spotify, Lettore multimediale e in generale con i programmi che compaiono in quei controlli. A differenza dell'app per Mac ferma anche i video senza audio, purché il programma esponga i controlli multimediali.

## ⚙️ Come è fatta

| File | Ruolo |
| --- | --- |
| `nodistraction/detector.py` | MediaPipe Face Landmarker: stesse soglie di `chrome-extension/detector.js` |
| `nodistraction/camera.py` | Webcam con OpenCV (DirectShow), elenco dei nomi, esclusione di quelle virtuali |
| `nodistraction/media.py` | Pausa e ripresa con `GlobalSystemMediaTransportControlsSessionManager` |
| `nodistraction/app.py` | Logica di pausa, icona nell'area di notifica, auto-test |
| `nodistraction/ui.py` | Pannello (customtkinter) con la stessa disposizione dell'app per Mac |
| `nodistraction/system.py` | Impostazioni in `%APPDATA%\NoDistraction`, avvio con Windows, suono, istanza singola |
| `build/` | `prepare.py` (risorse, versione), `NoDistraction.spec` (PyInstaller), `installer.iss` (Inno Setup) |

## 🏗️ Compilare

L'installer si compila su Windows, automaticamente con GitHub Actions ([`.github/workflows/windows.yml`](../.github/workflows/windows.yml)) a ogni modifica di `windows/`. Il workflow:

1. installa le dipendenze e prepara le risorse;
2. lancia l'**auto-test** (modello, analisi, controlli multimediali, risorse) dal codice;
3. crea l'eseguibile con PyInstaller e ripete l'auto-test sull'exe;
4. crea l'installer con Inno Setup;
5. **installa davvero** l'installer in modo silenzioso, ripete l'auto-test sull'app installata e la disinstalla;
6. pubblica l'installer come artefatto; avviato a mano con un tag, lo allega alla release.

In locale, su Windows:

```powershell
cd windows
pip install -r requirements.txt pyinstaller
python build/prepare.py
pyinstaller build/NoDistraction.spec --noconfirm --distpath dist --workpath build/work
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" build\installer.iss
```
