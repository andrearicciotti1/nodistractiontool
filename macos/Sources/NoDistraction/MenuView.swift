import AVFoundation
import SwiftUI

@main
struct NoDistractionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel

    private static let delays: [(String, Double)] = [
        ("0,7 secondi", 0.7), ("1,5 secondi", 1.5), ("3 secondi", 3), ("5 secondi", 5),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.phase.isRunning {
                CameraPreview(session: model.camera.session)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        if let name = model.activeCameraName {
                            Text(name)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
            }

            HStack {
                Button(model.phase.isRunning ? "Interrompi" : "Avvia") { model.toggle() }
                    .keyboardShortcut(.defaultAction)
                Button("Ricalibra") { model.recalibrate() }
                    .disabled(!model.phase.isRunning)
            }

            if !model.hasAccessibility {
                warning(
                    "Per mettere in pausa gli altri programmi serve il permesso Accessibilità.",
                    button: "Concedi permesso", action: model.requestAccessibility
                )
            }
            if case .error = model.phase {
                warning(model.statusText, button: "Apri Impostazioni", action: model.openCameraSettings)
            }

            Divider()

            Picker("Pausa dopo", selection: $model.pauseDelay) {
                ForEach(Self.delays, id: \.1) { Text($0.0).tag($0.1) }
            }
            Picker("Webcam", selection: $model.cameraID) {
                Text("Automatica (esclude virtuali)").tag("")
                ForEach(model.cameras) { camera in
                    Text(camera.isVirtual ? "\(camera.name) — virtuale" : camera.name).tag(camera.id)
                }
            }
            Toggle("Riprendi quando torno a guardare", isOn: $model.autoResume)
            Toggle("Suono di errore quando metto in pausa", isOn: $model.pauseSound)
            Toggle("Attiva all'apertura dell'app", isOn: $model.autoStart)
            Toggle("Apri al login", isOn: $model.launchAtLogin)

            if !model.lastAction.isEmpty {
                Text(model.lastAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("Analisi solo su questo Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Esci") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.menuIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Distraction").font(.headline)
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .watching: return .green
        case .calibrating, .starting, .away: return .orange
        case .paused, .error: return .red
        case .off: return .secondary
        }
    }

    private func warning(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Anteprima a specchio della webcam in uso.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
