import UIKit
import Vision
import os

enum OCRServiceError: LocalizedError {
    case noImage
    case noTextFound
    case visionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noImage: return "No image to scan."
        case .noTextFound: return "No Japanese text detected. Try moving closer or reducing glare."
        case .visionFailed(let error): return error.localizedDescription
        }
    }
}

struct OCRLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    /// Vision-normalized bbox in the *display-oriented* image space: origin bottom-left.
    let boundingBox: CGRect
    /// One bbox per Character of `text`, in the same Vision coordinate space.
    /// Empty if Vision couldn't resolve per-character boxes.
    let charBoxes: [CGRect]
}

final class OCRService {
    static let shared = OCRService()

    func recognize(in image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.cgImage else {
            AppLog.ocr.error("recognize called with no cgImage")
            throw OCRServiceError.noImage
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        AppLog.ocr.info("scan start size=\(cgImage.width, privacy: .public)x\(cgImage.height, privacy: .public)")

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    AppLog.ocr.error("vision failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: OCRServiceError.visionFailed(error))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: OCRServiceError.noTextFound)
                    return
                }

                let sorted = observations.sorted { lhs, rhs in
                    if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 0.02 {
                        return lhs.boundingBox.minY > rhs.boundingBox.minY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

                let lines = sorted.compactMap { obs -> OCRLine? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let text = candidate.string
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

                    var charBoxes: [CGRect] = []
                    charBoxes.reserveCapacity(text.count)
                    var idx = text.startIndex
                    while idx < text.endIndex {
                        let next = text.index(after: idx)
                        let box = (try? candidate.boundingBox(for: idx..<next))?.boundingBox ?? obs.boundingBox
                        charBoxes.append(box)
                        idx = next
                    }
                    return OCRLine(text: text, boundingBox: obs.boundingBox, charBoxes: charBoxes)
                }

                if lines.isEmpty {
                    continuation.resume(throwing: OCRServiceError.noTextFound)
                } else {
                    AppLog.ocr.info("scan recognised lines=\(lines.count, privacy: .public)")
                    continuation.resume(returning: lines)
                }
            }

            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                AppLog.ocr.error("vision handler perform failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: OCRServiceError.visionFailed(error))
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
