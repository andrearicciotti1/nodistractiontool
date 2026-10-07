import AppKit
import ApplicationServices
import CoreAudio

/// Un processo che sta mandando audio alle casse.
struct AudioProcess: Hashable {
    let pid: pid_t
    let bundleID: String
}

/// Elenco dei processi che stanno riproducendo audio (macOS 14.2+).
enum AudioProcesses {
    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    static func outputting() -> Set<AudioProcess> {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        var result = Set<AudioProcess>()
        for object in objects where value(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 {
            let pid = value(object, kAudioProcessPropertyPID, pid_t(0))
            result.insert(AudioProcess(pid: pid, bundleID: bundleID(of: object)))
        }
        return result
    }

    private static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var result = fallback
        var size = UInt32(MemoryLayout<T>.size)
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result)
        return result
    }

    private static func bundleID(of object: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &name) == noErr else { return "" }
        return name?.takeRetainedValue() as String? ?? ""
    }
}

/// Simula il tasto ⏯ della tastiera, che macOS consegna al programma in
/// riproduzione. Serve il permesso Accessibilità.
enum MediaKey {
    private static let playKeyCode = 16  // NX_KEYTYPE_PLAY

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func playPause() {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (playKeyCode << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// Mette in pausa e riprende la riproduzione di qualsiasi programma.
///
/// Il tasto ⏯ è un interruttore: premuto quando non suona niente farebbe
/// partire l'ultimo video. Per questo lo preme solo se qualche programma sta
/// davvero riproducendo audio, poi controlla che si sia fermato e annulla se
/// invece ha fatto partire qualcosa.
@MainActor
final class MediaPauser {
    // App di chiamata: il loro audio non va "messo in pausa".
    private static let ignoredBundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.FaceTime",
        "com.hnc.Discord", "com.tinyspeck.slackmacgap", "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram",
    ]
    private static let settleDelay: Duration = .milliseconds(900)

    private(set) var pausedSomething = false
    private var pausedProcesses = Set<AudioProcess>()
    private(set) var lastAction = ""

    private func playingMedia() -> Set<AudioProcess> {
        let me = ProcessInfo.processInfo.processIdentifier
        return AudioProcesses.outputting().filter {
            $0.pid != me && !Self.ignoredBundleIDs.contains($0.bundleID)
        }
    }

    func pause() async {
        guard MediaKey.hasPermission else {
            lastAction = "Manca il permesso Accessibilità"
            return
        }
        let before = playingMedia()
        guard !before.isEmpty else {
            lastAction = "Niente in riproduzione"
            return
        }

        MediaKey.playPause()
        try? await Task.sleep(for: Self.settleDelay)
        let after = playingMedia()
        let stopped = before.subtracting(after)
        let started = after.subtracting(before)

        if !started.isEmpty {
            // Ha fatto partire qualcos'altro: si torna com'era.
            MediaKey.playPause()
            lastAction = "Annullato: avrebbe avviato \(Self.names(started))"
            return
        }
        pausedSomething = !stopped.isEmpty
        pausedProcesses = stopped
        lastAction = pausedSomething ? "In pausa: \(Self.names(stopped))" : "Il programma non ha risposto al tasto ⏯"
    }

    func resume() async {
        guard pausedSomething else { return }
        pausedSomething = false
        // Se hai già fatto ripartire tu la riproduzione, non si tocca niente.
        let playing = playingMedia()
        if !pausedProcesses.isDisjoint(with: playing) {
            lastAction = "Già ripreso"
            return
        }
        MediaKey.playPause()
        lastAction = "Ripreso: \(Self.names(pausedProcesses))"
        pausedProcesses = []
    }

    /// Dimentica le pause fatte senza riprendere (per esempio all'arresto
    /// con la ripresa automatica disattivata).
    func forget() {
        pausedSomething = false
        pausedProcesses = []
    }

    private static func names(_ processes: Set<AudioProcess>) -> String {
        processes.map { process in
            NSRunningApplication(processIdentifier: process.pid)?.localizedName
                ?? (process.bundleID.isEmpty ? "processo \(process.pid)" : process.bundleID)
        }
        .sorted()
        .joined(separator: ", ")
    }
}
