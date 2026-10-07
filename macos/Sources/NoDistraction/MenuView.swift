import AVFoundation
import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    /// Chiamata quando cambia la misura del contenuto, per adattare il pannello.
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !model.hasAccessibility {
                Notice(
                    icon: "hand.raised.fill",
                    text: "Per mettere in pausa gli altri programmi serve il permesso Accessibilità.",
                    button: "Concedi permesso",
                    action: model.requestAccessibility
                )
            }
            if case .error(let message) = model.phase {
                Notice(
                    icon: "video.slash.fill",
                    text: message,
                    button: "Apri Impostazioni",
                    action: model.openCameraSettings
                )
            }

            if model.phase.isRunning {
                preview
            }

            SettingsGroup(title: "Pausa") {
                DelayControl(seconds: $model.pauseDelay)
                Divider()
                SettingToggle("Riprendi quando torno a guardare", isOn: $model.autoResume)
                SettingToggle("Suono di errore alla pausa", isOn: $model.pauseSound)
            }

            SettingsGroup(title: "Webcam") {
                Picker("Webcam", selection: $model.cameraID) {
                    Text("Automatica (esclude virtuali)").tag("")
                    ForEach(model.cameras) { camera in
                        Text(camera.isVirtual ? "\(camera.name) — virtuale" : camera.name).tag(camera.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsGroup(title: "Generale") {
                SettingToggle("Attiva all'apertura dell'app", isOn: $model.autoStart)
                SettingToggle("Apri al login", isOn: $model.launchAtLogin)
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ContentSizeKey.self) { onSizeChange($0) }
    }

    // MARK: - Parti

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.18))
                    Image(systemName: model.menuIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No Distraction")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(model.phase == .off ? .secondary : statusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: model.toggle) {
                    Label(
                        model.phase.isRunning ? "Interrompi" : "Avvia",
                        systemImage: model.phase.isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.phase.isRunning ? .red : .accentColor)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                if model.phase.isRunning {
                    Button(action: model.recalibrate) {
                        Image(systemName: "scope")
                            .frame(width: 22)
                    }
                    .controlSize(.large)
                    .help("Ricalibra: guarda lo schermo per 3 secondi")
                }
            }
        }
    }

    private var preview: some View {
        CameraPreview(session: model.camera.session)
            .frame(height: 180)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(previewLabel)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                if let name = model.activeCameraName {
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(8)
                }
            }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let action = visibleLastAction {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text(action)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Analisi solo su questo Mac")
            }
            Spacer(minLength: 8)
            Button("Esci") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: - Dati derivati

    private var visibleLastAction: String? {
        let action = model.lastAction
        if action.isEmpty { return nil }
        // L'avviso dedicato in alto lo dice già.
        if !model.hasAccessibility && action.contains("Accessibilità") { return nil }
        return action
    }

    private var previewLabel: String {
        switch model.phase {
        case .calibrating(let progress, let faceFound): return faceFound ? "Calibrazione \(progress)%" : "Volto non rilevato"
        case .watching: return "Stai guardando"
        case .away(let reason): return reason
        case .paused: return "In pausa"
        default: return model.statusText
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
}

// MARK: - Componenti

/// Riquadro con titolo, come i gruppi di Impostazioni di Sistema.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 9) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}

private struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

private struct Notice: View {
    let icon: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .font(.system(size: 14))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Button(button, action: action)
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.13))
        )
    }
}

/// Ritardo prima della pausa: slider da 0,3 a 30 secondi con scala
/// logaritmica (fine sui valori brevi), più − / + per la regolazione fine.
struct DelayControl: View {
    @Binding var seconds: Double

    static let range: ClosedRange<Double> = 0.3...30

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Metti in pausa dopo")
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                stepButton("minus", direction: -1, disabled: seconds <= Self.range.lowerBound)
                Text(Self.format(seconds))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 42)
                stepButton("plus", direction: 1, disabled: seconds >= Self.range.upperBound)
            }
            Slider(value: sliderPosition, in: 0...1)
                .controlSize(.small)
            HStack {
                Text(Self.format(Self.range.lowerBound))
                Spacer()
                Text("più fine sui valori brevi")
                Spacer()
                Text(Self.format(Self.range.upperBound))
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }

    /// Posizione dello slider in [0, 1] ↔ secondi, su scala logaritmica.
    private var sliderPosition: Binding<Double> {
        let low = Self.range.lowerBound, ratio = Self.range.upperBound / low
        return Binding(
            get: { log(max(seconds, low) / low) / log(ratio) },
            set: { seconds = Self.rounded(low * pow(ratio, $0)) }
        )
    }

    private func stepButton(_ symbol: String, direction: Double, disabled: Bool) -> some View {
        Button { nudge(direction) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(disabled ? 0.04 : 0.1)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .primary)
        .disabled(disabled)
        .help(direction > 0 ? "Aumenta" : "Diminuisci")
    }

    private func nudge(_ direction: Double) {
        let step = Self.step(for: direction > 0 ? seconds : seconds - 0.001)
        let next = Self.rounded(seconds + direction * step)
        seconds = min(max(next, Self.range.lowerBound), Self.range.upperBound)
    }

    private static func step(for value: Double) -> Double {
        switch value {
        case ..<3: return 0.1
        case ..<10: return 0.5
        default: return 1
        }
    }

    static func rounded(_ value: Double) -> Double {
        let step = step(for: value)
        let result = (value / step).rounded() * step
        return min(max((result * 10).rounded() / 10, range.lowerBound), range.upperBound)
    }

    static func format(_ value: Double) -> String {
        let text = value >= 10 || abs(value - value.rounded()) < 0.05
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        return "\(text) s"
    }
}

private struct ContentSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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
