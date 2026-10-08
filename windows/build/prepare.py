"""Prepara le risorse per la build Windows: modello MediaPipe, immagini
dell'installer e versione. Si lancia dalla cartella windows/."""

from pathlib import Path
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
WINDOWS = ROOT / "windows"
BUILD = WINDOWS / "build"
ASSETS = WINDOWS / "assets"

sys.path.insert(0, str(WINDOWS))
from nodistraction import __version__  # noqa: E402

# Il modello è lo stesso dell'estensione Chrome: non lo duplichiamo nella repo.
shutil.copy(ROOT / "chrome-extension" / "models" / "face_landmarker.task", ASSETS / "face_landmarker.task")

icon = Image.open(ROOT / "branding" / "icon-1024.png").convert("RGBA")


def gradient(size, top, bottom):
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        draw.line([(0, y), (width, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return image


def font(size, bold=False):
    for name in (["segoeuib.ttf", "arialbd.ttf"] if bold else ["segoeui.ttf", "arial.ttf"]):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


# Immagine grande della procedura guidata (164×314 e versioni per schermi ad alta densità).
large_files = []
for scale in (1, 1.5, 2):
    w, h = round(164 * scale), round(314 * scale)
    image = gradient((w, h), (110, 99, 255), (34, 18, 94))
    side = round(110 * scale)
    image.paste(icon.resize((side, side), Image.LANCZOS), ((w - side) // 2, round(70 * scale)), icon.resize((side, side), Image.LANCZOS))
    draw = ImageDraw.Draw(image)
    title = "No Distraction"
    f = font(round(17 * scale), bold=True)
    tw = draw.textlength(title, font=f)
    draw.text(((w - tw) / 2, round(200 * scale)), title, font=f, fill="white")
    sub = f"versione {__version__}"
    f2 = font(round(11 * scale))
    sw = draw.textlength(sub, font=f2)
    draw.text(((w - sw) / 2, round(226 * scale)), sub, font=f2, fill=(220, 215, 255))
    path = BUILD / f"wizard-large-{int(scale * 100)}.bmp"
    image.save(path)
    large_files.append(path.name)

# Immagine piccola in alto a destra (55×55 e multipli).
small_files = []
for scale in (1, 1.5, 2):
    side = round(55 * scale)
    image = Image.new("RGB", (side, side), "white")
    image.paste(icon.resize((side, side), Image.LANCZOS), (0, 0), icon.resize((side, side), Image.LANCZOS))
    path = BUILD / f"wizard-small-{int(scale * 100)}.bmp"
    image.save(path)
    small_files.append(path.name)

(BUILD / "generated.iss").write_text(
    f'#define AppVersion "{__version__}"\n'
    f'#define WizardLarge "{",".join(large_files)}"\n'
    f'#define WizardSmall "{",".join(small_files)}"\n',
    encoding="utf-8",
)

# Proprietà dell'eseguibile (Dettagli nel menu Proprietà di Windows).
parts = (__version__.split(".") + ["0", "0", "0"])[:4]
numbers = ", ".join(parts)
(BUILD / "version_info.txt").write_text(f"""VSVersionInfo(
  ffi=FixedFileInfo(filevers=({numbers}), prodvers=({numbers})),
  kids=[
    StringFileInfo([StringTable('041004B0', [
      StringStruct('CompanyName', 'Andrea Ricciotti'),
      StringStruct('FileDescription', 'No Distraction'),
      StringStruct('FileVersion', '{__version__}'),
      StringStruct('InternalName', 'NoDistraction'),
      StringStruct('LegalCopyright', '© 2026 Andrea Ricciotti'),
      StringStruct('OriginalFilename', 'NoDistraction.exe'),
      StringStruct('ProductName', 'No Distraction'),
      StringStruct('ProductVersion', '{__version__}')])]),
    VarFileInfo([VarStruct('Translation', [0x0410, 1200])])
  ]
)
""", encoding="utf-8")
print(f"Risorse pronte per la versione {__version__}")
