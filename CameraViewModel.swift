import Combine
import Foundation

@MainActor
final class CameraViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case photo
        case barcode
        case aiVision

        var id: String { rawValue }

        var title: String {
            switch self {
            case .photo:
                return "Photo"
            case .barcode:
                return "Barcode"
            case .aiVision:
                return "AI Vision"
            }
        }

        var iconName: String {
            switch self {
            case .photo:
                return "camera"
            case .barcode:
                return "barcode.viewfinder"
            case .aiVision:
                return "sparkles"
            }
        }
    }

    @Published var selectedMode: Mode = .photo
    @Published var capturedImageData: Data?
    @Published var recognizedProduct: ProductRecognitionResult?
    @Published var isRecognizing = false
    @Published var statusMessage = "AI product recognition is not available yet."
    @Published var focusPoint: CGPoint?

    let cameraService: CameraService

    private let recognitionService: ProductRecognitionServicing

    init() {
        self.cameraService = CameraService()
        self.recognitionService = ProductRecognitionService()
    }

    init(
        cameraService: CameraService,
        recognitionService: ProductRecognitionServicing
    ) {
        self.cameraService = cameraService
        self.recognitionService = recognitionService
    }

    var canAddProduct: Bool {
        recognizedProduct != nil
    }

    func startCamera() {
        cameraService.requestAccessAndConfigure()
    }

    func stopCamera() {
        cameraService.stop()
    }

    func toggleFlash() {
        cameraService.toggleFlash()
    }

    func focus(at point: CGPoint) {
        focusPoint = point
        cameraService.focus(at: point)
        statusMessage = "Focus locked."
    }

    func zoom(to zoomFactor: CGFloat) {
        cameraService.setZoomFactor(zoomFactor)
    }

    func capturePhoto() {
        clearRecognition()
        statusMessage = selectedMode == .aiVision
            ? "Waiting for product analysis."
            : "Taking photo..."

        cameraService.capturePhoto { [weak self] result in
            guard let self else {
                return
            }

            Task { @MainActor in
                switch result {
                case .success(let photo):
                    self.capturedImageData = photo.data
                    await self.recognizeIfNeeded(from: photo.data)
                case .failure:
                    self.statusMessage = "Photo capture failed. Please try again."
                }
            }
        }
    }

    func handleSelectedPhotoData(_ data: Data?) {
        clearRecognition()

        guard let data else {
            statusMessage = "We could not load that photo. Please choose another one."
            return
        }

        capturedImageData = data

        Task {
            await recognizeIfNeeded(from: data)
        }
    }

    func resetCapture() {
        capturedImageData = nil
        clearRecognition()
        statusMessage = "AI product recognition is not available yet."
    }

    private func recognizeIfNeeded(from imageData: Data) async {
        guard selectedMode == .aiVision else {
            statusMessage = "Photo captured successfully. Ready for AI recognition."
            return
        }

        isRecognizing = true
        statusMessage = "Waiting for product analysis."
        defer { isRecognizing = false }

        do {
            recognizedProduct = try await recognitionService.recognizeProduct(from: imageData)
            statusMessage = recognizedProduct == nil
                ? "AI product recognition is not available yet."
                : "Product recognized."
        } catch {
            statusMessage = "Product analysis is unavailable right now."
        }
    }

    private func clearRecognition() {
        recognizedProduct = nil
        isRecognizing = false
    }
}
