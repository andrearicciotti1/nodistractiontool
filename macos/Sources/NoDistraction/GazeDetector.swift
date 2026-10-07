import CoreVideo
import Foundation
import Vision

/// Esito dell'analisi di un fotogramma.
enum GazeResult: Equatable {
    case noFace(calibrating: Bool)
    case calibrating(progress: Int)
    /// `awayReason` è nil quando stai guardando lo schermo.
    case tracking(awayReason: String?)
}

/// Stima posa della testa e stato degli occhi con Vision e li confronta con la
/// posizione "neutra" registrata in calibrazione. L'analisi gira sulla coda
/// della webcam, la ricalibrazione arriva dal thread principale: lo stato è
/// protetto da un lock.
final class GazeDetector: @unchecked Sendable {
    private struct Sample {
        var yaw: Double
        var pitch: Double
        var eyeOpenness: Double
        var pupilX: Double
        var pupilY: Double
    }

    // Soglie: oltre questi scostamenti dalla calibrazione lo sguardo è "altrove".
    private static let calibrationSamples = 30
    private static let yawLimit = 0.38          // radianti, circa 22°
    private static let pitchLimit = 0.30        // radianti, circa 17°
    private static let eyesClosedRatio = 0.50   // apertura rispetto alla calibrazione
    private static let pupilSideLimit = 0.22    // frazione della larghezza dell'occhio
    private static let pupilDownLimit = 0.22    // frazione dell'altezza dell'occhio
    private static let smoothing = 0.35

    private var samples: [Sample] = []
    private var baseline: Sample?
    private var smoothed: Sample?
    private let lock = NSLock()

    func recalibrate() {
        lock.lock()
        defer { lock.unlock() }
        samples = []
        baseline = nil
        smoothed = nil
    }

    private var isCalibrating: Bool {
        lock.lock()
        defer { lock.unlock() }
        return baseline == nil
    }

    func analyze(_ pixelBuffer: CVPixelBuffer) -> GazeResult {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return .noFace(calibrating: isCalibrating)
        }

        // Se ci sono più volti si prende il più grande, cioè il più vicino.
        let face = request.results?.max { first, second in
            first.boundingBox.width * first.boundingBox.height
                < second.boundingBox.width * second.boundingBox.height
        }
        lock.lock()
        defer { lock.unlock() }
        guard let face, let raw = Self.sample(from: face) else {
            return .noFace(calibrating: baseline == nil)
        }

        let current = smooth(raw)
        guard let baseline else {
            samples.append(raw)
            let progress = min(100, samples.count * 100 / Self.calibrationSamples)
            if samples.count >= Self.calibrationSamples {
                self.baseline = Self.median(of: samples)
            }
            return .calibrating(progress: progress)
        }

        return .tracking(awayReason: Self.awayReason(current: current, raw: raw, baseline: baseline))
    }

    private func smooth(_ sample: Sample) -> Sample {
        guard var value = smoothed else {
            smoothed = sample
            return sample
        }
        let a = Self.smoothing
        value.yaw += a * (sample.yaw - value.yaw)
        value.pitch += a * (sample.pitch - value.pitch)
        value.eyeOpenness += a * (sample.eyeOpenness - value.eyeOpenness)
        value.pupilX += a * (sample.pupilX - value.pupilX)
        value.pupilY += a * (sample.pupilY - value.pupilY)
        smoothed = value
        return value
    }

    private static func awayReason(current: Sample, raw: Sample, baseline: Sample) -> String? {
        if abs(current.yaw - baseline.yaw) > yawLimit { return "Testa girata" }
        if abs(current.pitch - baseline.pitch) > pitchLimit { return "Testa inclinata" }
        if baseline.eyeOpenness > 0, current.eyeOpenness < baseline.eyeOpenness * eyesClosedRatio {
            return "Occhi chiusi"
        }
        if abs(current.pupilX - baseline.pupilX) > pupilSideLimit { return "Sguardo di lato" }
        // In Vision l'asse y cresce verso l'alto: guardare in basso lo riduce.
        if baseline.pupilY - current.pupilY > pupilDownLimit { return "Sguardo in basso" }
        return nil
    }

    private static func sample(from face: VNFaceObservation) -> Sample? {
        guard
            let landmarks = face.landmarks,
            let leftEye = landmarks.leftEye?.normalizedPoints,
            let rightEye = landmarks.rightEye?.normalizedPoints,
            leftEye.count >= 4, rightEye.count >= 4
        else { return nil }

        let left = eyeMetrics(eye: leftEye, pupil: landmarks.leftPupil?.normalizedPoints.first)
        let right = eyeMetrics(eye: rightEye, pupil: landmarks.rightPupil?.normalizedPoints.first)
        return Sample(
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            eyeOpenness: (left.openness + right.openness) / 2,
            pupilX: (left.pupilX + right.pupilX) / 2,
            pupilY: (left.pupilY + right.pupilY) / 2
        )
    }

    /// Apertura (altezza/larghezza) e posizione della pupilla dentro l'occhio,
    /// entrambe normalizzate sul riquadro dell'occhio.
    private static func eyeMetrics(eye: [CGPoint], pupil: CGPoint?) -> (openness: Double, pupilX: Double, pupilY: Double) {
        let xs = eye.map(\.x), ys = eye.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let width = max(Double(maxX - minX), 0.0001)
        let height = max(Double(maxY - minY), 0.0001)
        let pupil = pupil ?? CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return (
            height / width,
            Double(pupil.x - minX) / width,
            Double(pupil.y - minY) / height
        )
    }

    private static func median(of samples: [Sample]) -> Sample {
        func mid(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        }
        return Sample(
            yaw: mid(samples.map(\.yaw)),
            pitch: mid(samples.map(\.pitch)),
            eyeOpenness: mid(samples.map(\.eyeOpenness)),
            pupilX: mid(samples.map(\.pupilX)),
            pupilY: mid(samples.map(\.pupilY))
        )
    }
}
