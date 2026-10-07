import AVFoundation
import CoreVideo

struct CameraInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let isVirtual: Bool
}

enum CameraError: LocalizedError {
    case denied
    case notFound
    case cannotOpen(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "macOS non permette a No Distraction di usare la webcam. Attivala in Impostazioni di Sistema › Privacy e sicurezza › Fotocamera."
        case .notFound:
            return "Nessuna webcam trovata."
        case .cannotOpen(let detail):
            return "Impossibile aprire la webcam: \(detail)"
        }
    }
}

/// Gestisce la sessione di acquisizione e passa al massimo `framesPerSecond`
/// fotogrammi al secondo a `onFrame`, sulla propria coda.
final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // Webcam virtuali (OBS ecc.) scartate in automatico: senza il programma
    // che le alimenta mandano un'immagine fissa.
    private static let virtualPattern = try! NSRegularExpression(
        pattern: "obs|virtual|snap camera|mmhmm|manycam|xsplit|ndi|droidcam|iriun|camo",
        options: .caseInsensitive
    )
    private static let framesPerSecond = 10.0

    let session = AVCaptureSession()
    var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
    private let queue = DispatchQueue(label: "nodistraction.camera")
    private var lastFrame = Date.distantPast
    private(set) var activeCamera: CameraInfo?

    static func availableCameras() -> [CameraInfo] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types += [.external, .continuityCamera]
        } else {
            types.append(.externalUnknown)
        }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices
        return devices.map { device in
            let name = device.localizedName
            let range = NSRange(name.startIndex..., in: name)
            let isVirtual = virtualPattern.firstMatch(in: name, range: range) != nil
            return CameraInfo(id: device.uniqueID, name: name, isVirtual: isVirtual)
        }
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Avvia la webcam scelta; con `preferredID` vuoto usa la prima non virtuale.
    func start(preferredID: String) throws {
        let cameras = Self.availableCameras()
        let chosen = cameras.first { $0.id == preferredID }
            ?? cameras.first { !$0.isVirtual }
            ?? cameras.first
        guard let chosen, let device = AVCaptureDevice(uniqueID: chosen.id) else {
            throw CameraError.notFound
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.cannotOpen(error.localizedDescription)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.cannotOpen("configurazione non supportata")
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        activeCamera = chosen
        queue.async { self.session.startRunning() }
    }

    func stop() {
        queue.async {
            self.session.stopRunning()
            self.session.beginConfiguration()
            self.session.inputs.forEach(self.session.removeInput)
            self.session.outputs.forEach(self.session.removeOutput)
            self.session.commitConfiguration()
        }
        activeCamera = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrame) >= 1 / Self.framesPerSecond,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        onFrame?(pixelBuffer)
    }
}
