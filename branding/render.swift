// Disegna gli asset grafici di No Distraction:
//   swift render.swift icon <file.png> <lato>
//   swift render.swift dmg  <file.png> <scala>   (sfondo DMG 660×400 punti)
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    print("uso: swift render.swift icon|dmg <file.png> <lato|scala>")
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func save(_ context: CGContext, to path: String) {
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// Contorno a mandorla dell'occhio centrato in `center`.
func eyePath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let left = CGPoint(x: center.x - width / 2, y: center.y)
    let right = CGPoint(x: center.x + width / 2, y: center.y)
    path.move(to: left)
    path.addCurve(to: right,
                  control1: CGPoint(x: center.x - width * 0.22, y: center.y + height * 0.66),
                  control2: CGPoint(x: center.x + width * 0.22, y: center.y + height * 0.66))
    path.addCurve(to: left,
                  control1: CGPoint(x: center.x + width * 0.22, y: center.y - height * 0.66),
                  control2: CGPoint(x: center.x - width * 0.22, y: center.y - height * 0.66))
    path.closeSubpath()
    return path
}

/// L'occhio con il simbolo di pausa al posto della pupilla, in un riquadro di lato `size`.
func drawEye(_ c: CGContext, center: CGPoint, size: CGFloat) {
    let eyeWidth = size * 0.74, eyeHeight = size * 0.40
    let eye = eyePath(center: center, width: eyeWidth, height: eyeHeight)

    // Bianco dell'occhio, con ombra morbida.
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.05, color: color(0x0B0630, 0.45))
    c.addPath(eye)
    c.setFillColor(color(0xFFFFFF))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(eye)
    c.clip()
    c.drawLinearGradient(gradient([color(0xFFFFFF), color(0xE4E1FF)], [0, 1]),
                         start: CGPoint(x: center.x, y: center.y + eyeHeight / 2),
                         end: CGPoint(x: center.x, y: center.y - eyeHeight / 2), options: [])

    // Iride.
    let irisRadius = size * 0.165
    c.drawRadialGradient(gradient([color(0x9C7BFF), color(0x5B3DF0), color(0x2E1A9E)], [0, 0.6, 1]),
                         startCenter: CGPoint(x: center.x - irisRadius * 0.25, y: center.y + irisRadius * 0.3), startRadius: 0,
                         endCenter: center, endRadius: irisRadius, options: [])
    // Pupilla scura.
    let pupilRadius = irisRadius * 0.58
    c.setFillColor(color(0x120A3A))
    c.fillEllipse(in: CGRect(x: center.x - pupilRadius, y: center.y - pupilRadius, width: pupilRadius * 2, height: pupilRadius * 2))
    // Simbolo di pausa.
    let barWidth = pupilRadius * 0.30, barHeight = pupilRadius * 0.98, gap = pupilRadius * 0.24
    c.setFillColor(color(0xFFFFFF))
    for dx in [-(gap / 2 + barWidth), gap / 2] {
        let bar = CGRect(x: center.x + dx, y: center.y - barHeight / 2, width: barWidth, height: barHeight)
        c.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        c.fillPath()
    }
    // Riflesso.
    let glint = irisRadius * 0.20
    c.setFillColor(color(0xFFFFFF, 0.9))
    c.fillEllipse(in: CGRect(x: center.x + irisRadius * 0.38, y: center.y + irisRadius * 0.38, width: glint, height: glint))
    c.restoreGState()

    // Contorno sottile dell'occhio.
    c.addPath(eye)
    c.setStrokeColor(color(0x1B0F55, 0.25))
    c.setLineWidth(size * 0.006)
    c.strokePath()
}

func renderIcon(side: Int, to path: String) {
    let s = CGFloat(side)
    let c = makeContext(width: side, height: side)
    // Griglia delle icone macOS: riquadro di 824/1024 con angoli continui.
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.35))
    c.addPath(squircle)
    c.setFillColor(color(0x3A2BC4))
    c.fillPath()
    c.restoreGState()

    c.saveGState()
    c.addPath(squircle)
    c.clip()
    c.drawLinearGradient(gradient([color(0x6E63FF), color(0x4A33D8), color(0x22125E)], [0, 0.5, 1]),
                         start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // Bagliore in alto.
    c.drawRadialGradient(gradient([color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)], [0, 1]),
                         startCenter: CGPoint(x: rect.midX, y: rect.maxY), startRadius: 0,
                         endCenter: CGPoint(x: rect.midX, y: rect.maxY), endRadius: rect.width * 0.75, options: [])
    c.restoreGState()

    // Bordo interno luminoso.
    c.addPath(squircle)
    c.setStrokeColor(color(0xFFFFFF, 0.18))
    c.setLineWidth(s * 0.004)
    c.strokePath()

    drawEye(c, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.width)
    save(c, to: path)
}

func renderDMGBackground(scale: CGFloat, to path: String) {
    // Sfondo chiaro: Finder scrive i nomi delle icone in nero e non si può
    // cambiare. Le istruzioni stanno subito sotto le icone perché, se l'utente
    // ha attive barra del percorso e di stato, Finder copre il fondo.
    let width: CGFloat = 660, height: CGFloat = 400
    let c = makeContext(width: Int(width * scale), height: Int(height * scale))
    c.scaleBy(x: scale, y: scale)

    c.drawLinearGradient(gradient([color(0xFBFAFF), color(0xECE9FF)], [0, 1]),
                         start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
    c.drawRadialGradient(gradient([color(0x8B7CFF, 0.22), color(0x8B7CFF, 0)], [0, 1]),
                         startCenter: CGPoint(x: width / 2, y: height + 60), startRadius: 0,
                         endCenter: CGPoint(x: width / 2, y: height + 60), endRadius: 380, options: [])

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, hex: UInt32, alpha: CGFloat = 1, top: CGFloat, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color(hex, alpha))!,
            .kern: tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        // `top` è la linea di base misurata dall'alto, come in Finder.
        c.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX, y: height - top)
        CTLineDraw(line, c)
    }

    text("No Distraction", size: 26, weight: .bold, hex: 0x1E1550, top: 52)
    text("Mette in pausa i video quando smetti di guardare lo schermo", size: 12.5, weight: .regular, hex: 0x5A5480, top: 74)

    // Freccia tra l'app (x 175) e Applicazioni (x 485), all'altezza delle icone (y 175).
    let arrowY = height - 175
    c.setStrokeColor(color(0x6A5CFF, 0.75))
    c.setLineWidth(3)
    c.setLineCap(.round)
    c.setLineDash(phase: 0, lengths: [1, 9])
    c.move(to: CGPoint(x: 268, y: arrowY))
    c.addLine(to: CGPoint(x: 382, y: arrowY))
    c.strokePath()
    c.setLineDash(phase: 0, lengths: [])
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 376, y: arrowY + 11))
    c.addLine(to: CGPoint(x: 390, y: arrowY))
    c.addLine(to: CGPoint(x: 376, y: arrowY - 11))
    c.strokePath()

    // Sotto i nomi delle icone (circa y 255).
    c.setFillColor(color(0x1E1550, 0.08))
    c.fill(CGRect(x: 150, y: height - 278, width: 360, height: 1))
    text("Trascina l'app nella cartella Applicazioni", size: 13, weight: .semibold, hex: 0x2A2250, top: 300)
    text("Primo avvio: clic destro sull'app › Apri, poi consenti webcam e Accessibilità", size: 11, weight: .regular, hex: 0x6A6590, top: 320)
    text("ANALISI DELLA WEBCAM SOLO SU QUESTO MAC", size: 9, weight: .semibold, hex: 0x8A85A8, top: 352, tracking: 1.5)

    save(c, to: path)
}

switch args[1] {
case "icon": renderIcon(side: Int(args[3])!, to: args[2])
case "dmg": renderDMGBackground(scale: CGFloat(Double(args[3])!), to: args[2])
default: print("tipo sconosciuto: \(args[1])"); exit(1)
}
