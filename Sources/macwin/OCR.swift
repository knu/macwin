import CoreGraphics
import Vision

func recognizeText(
    in image: CGImage,
    cropRect: Rect,
    name: String?,
    languages: [String],
    minConfidence: Float
) throws -> [OCRToken] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])

    return (request.results ?? []).compactMap { observation in
        guard let candidate = observation.topCandidates(1).first, candidate.confidence >= minConfidence else {
            return nil
        }
        let bbox = observation.boundingBox
        let rect = Rect(
            originX: cropRect.originX + bbox.minX * cropRect.width,
            originY: cropRect.originY + (1 - bbox.maxY) * cropRect.height,
            width: bbox.width * cropRect.width,
            height: bbox.height * cropRect.height
        )
        return OCRToken(name: name, text: candidate.string, confidence: candidate.confidence, bbox: rect)
    }
}
