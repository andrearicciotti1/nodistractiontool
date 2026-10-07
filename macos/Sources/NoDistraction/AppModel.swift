import AppKit
import AVFoundation
import Combine
import ServiceManagement

enum Phase: Equatable {
    case off
    case starting
    case calibrating(progress: Int, faceFound: Bool)
    case watching
    case away(reason: String)
    case paused(reason: String)
    case error(String)

    var isRunning: Bool {
        switch self {
        case .off, .error: return false
        default: return true
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let resumeAfter: TimeInterval = 0.4

    @Published private(set) var phase: Phase = .off
    @Published private(set) var cameras: [CameraInfo] = []
    @Published private(set) var activeCameraName: String?
    @Published private(set) var lastAction = ""
    @Published private(set) var hasAccessibility = MediaKey.hasPermission

    // Impostazioni, salvate in UserDefaults.
    @Published var pauseDelay: Double { didSet { defaults.set(pauseDelay, forKey: "pauseDelay") } }
    @Published var autoResume: Bool { didSet { defaults.set(autoResume, forKey: "autoResume") } }
    @Published var pauseSound: Bool { didSet { defaults.set(pauseSound, forKey: "pauseSound") } }
    @Published var autoStart: Bool { didSet { defaults.set(autoStart, forKey: "autoStart") } }
    @Published var cameraID: String {
        didSet {
            defaults.set(cameraID, forKey: "cameraID")
            if phase.isRunning { restart() }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
    }

    let camera = CameraService()
    private nonisolated let detector = GazeDetector()
    private let pauser = MediaPauser()
    private let defaults = UserDefaults.standard
    private let errorSound: NSSound?
    private var awaySince: Date?
    private var backSince: Date?
    private var videosPaused = false
    private var permissionTimer: Timer?
    // Pausa e ripresa vanno eseguite in ordine: la pausa impiega quasi un
    // secondo a verificare l'effetto.
    private var mediaTask: Task<Void, Never>?

    init() {
        defaults.register(defaults: [
            "pauseDelay": 1.5, "autoResume": true, "pauseSound": true, "autoStart": true,
        ])
        pauseDelay = defaults.double(forKey: "pauseDelay")
        autoResume = defaults.bool(forKey: "autoResume")
        pauseSound = defaults.bool(forKey: "pauseSound")
        autoStart = defaults.bool(forKey: "autoStart")
        cameraID = defaults.string(forKey: "cameraID") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        errorSound = Bundle.main.url(forResource: "error", withExtension: "mp3")
            .flatMap { NSSound(contentsOf: $0, byReference: true) }

        cameras = CameraService.availableCameras()
        let detector = self.detector
        camera.onFrame = { @Sendable [weak self] buffer in
            let result = detector.analyze(buffer)
            Task { @MainActor in self?.handle(result) }
        }

        // Il permesso Accessibilità si concede in Impostazioni: lo si ricontrolla
        // ogni tanto per aggiornare il menu.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.hasAccessibility = MediaKey.hasPermission }
        }

        if autoStart { Task { await start() } }
    }

    var menuIcon: String {
        switch phase {
        case .off: return "eye.slash"
        case .starting, .calibrating: return "eye.circle"
        case .watching: return "eye"
        case .away: return "eye.trianglebadge.exclamationmark"
        case .paused: return "pause.circle.fill"
        case .error: return "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch phase {
        case .off: return "Non attivo"
        case .starting: return "Avvio…"
        case .calibrating(let progress, let faceFound):
            return faceFound ? "Calibrazione \(progress)% — guarda lo schermo" : "Volto non rilevato"
        case .watching: return "Stai guardando"
        case .away(let reason): return "\(reason)…"
        case .paused(let reason): return "In pausa — \(reason)"
        case .error(let message): return message
        }
    }

    // MARK: - Avvio e arresto

    func start() async {
        guard !phase.isRunning else { return }
        phase = .starting
        guard await CameraService.requestAccess() else {
            phase = .error(CameraError.denied.errorDescription!)
            return
        }
        cameras = CameraService.availableCameras()
        do {
            detector.recalibrate()
            try camera.start(preferredID: cameraID)
            activeCameraName = camera.activeCamera?.name
            awaySince = nil
            backSince = nil
            phase = .calibrating(progress: 0, faceFound: true)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stop() {
        camera.stop()
        activeCameraName = nil
        if videosPaused {
            videosPaused = false
            if autoResume { enqueueMedia { await $0.resume() } }
            else { enqueueMedia { $0.forget() } }
        }
        phase = .off
    }

    func toggle() {
        if phase.isRunning { stop() } else { Task { await start() } }
    }

    func recalibrate() {
        guard phase.isRunning else { return }
        detector.recalibrate()
        phase = .calibrating(progress: 0, faceFound: true)
    }

    private func restart() {
        stop()
        Task { await start() }
    }

    func requestAccessibility() {
        MediaKey.requestPermission()
    }

    func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            lastAction = "Avvio al login non riuscito: \(error.localizedDescription)"
        }
    }

    // MARK: - Logica di pausa

    private func handle(_ result: GazeResult) {
        guard phase.isRunning else { return }
        let now = Date()
        let reason: String?
        switch result {
        case .calibrating(let progress):
            phase = .calibrating(progress: progress, faceFound: true)
            return
        case .noFace(let calibrating):
            if calibrating {
                phase = .calibrating(progress: 0, faceFound: false)
                return
            }
            reason = "Volto assente"
        case .tracking(let awayReason):
            reason = awayReason
        }

        if let reason {
            backSince = nil
            if awaySince == nil { awaySince = now }
            if !videosPaused, let since = awaySince, now.timeIntervalSince(since) >= pauseDelay {
                pauseMedia()
            }
            phase = videosPaused ? .paused(reason: reason) : .away(reason: reason)
        } else {
            awaySince = nil
            if videosPaused {
                if backSince == nil { backSince = now }
                if let since = backSince, now.timeIntervalSince(since) >= Self.resumeAfter {
                    resumeMedia()
                }
            }
            phase = videosPaused ? .paused(reason: "torna a guardare") : .watching
        }
    }

    private func pauseMedia() {
        videosPaused = true
        if pauseSound {
            errorSound?.stop()
            errorSound?.play()
        }
        enqueueMedia { await $0.pause() }
    }

    private func resumeMedia() {
        videosPaused = false
        if autoResume { enqueueMedia { await $0.resume() } }
        else { enqueueMedia { $0.forget() } }
    }

    private func enqueueMedia(_ operation: @escaping @MainActor (MediaPauser) async -> Void) {
        let previous = mediaTask
        mediaTask = Task { [pauser] in
            await previous?.value
            await operation(pauser)
            lastAction = pauser.lastAction
        }
    }
}
