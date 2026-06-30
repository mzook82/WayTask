import Combine
import Foundation
import Photos

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
    @Published var pendingPhotoData: Data?
    @Published var capturedImageData: Data?
    @Published var recognizedProduct: ProductRecognitionResult?
    @Published var isRecognizing = false
    @Published var isSavingPhoto = false
    @Published var statusMessage = "AI recognition is not available yet."
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

    var isShowingPhotoPreview: Bool {
        pendingPhotoData != nil
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
        guard pendingPhotoData == nil else {
            return
        }

        focusPoint = point
        cameraService.focus(at: point)
        statusMessage = "Focus locked."
    }

    func zoom(to zoomFactor: CGFloat) {
        guard pendingPhotoData == nil else {
            return
        }

        cameraService.setZoomFactor(zoomFactor)
    }

    func capturePhoto() {
        clearRecognition()
        pendingPhotoData = nil
        statusMessage = "Taking photo..."

        cameraService.capturePhoto { [weak self] result in
            guard let self else {
                return
            }

            Task { @MainActor in
                switch result {
                case .success(let photo):
                    self.pendingPhotoData = photo.data
                    self.statusMessage = "Review your photo before using it."
                case .failure:
                    self.statusMessage = "Photo capture failed. Please try again."
                }
            }
        }
    }

    func handleSelectedPhotoData(_ data: Data?) {
        clearRecognition()
        pendingPhotoData = nil

        guard let data else {
            statusMessage = "We could not load that photo. Please choose another one."
            return
        }

        pendingPhotoData = data
        statusMessage = "Review your photo before using it."
    }

    func usePendingPhoto() {
        guard let pendingPhotoData else {
            return
        }

        capturedImageData = pendingPhotoData
        self.pendingPhotoData = nil
        clearRecognition()
        statusMessage = "Photo captured. Ready for AI recognition."
    }

    func retakePhoto() {
        pendingPhotoData = nil
        capturedImageData = nil
        clearRecognition()
        statusMessage = "AI recognition is not available yet."
    }

    func savePendingPhotoToLibrary() {
        guard let pendingPhotoData else {
            statusMessage = "No photo is ready to save."
            return
        }

        isSavingPhoto = true
        statusMessage = "Saving photo..."

        Task {
            let authorized = await requestPhotoLibraryAddPermission()

            guard authorized else {
                isSavingPhoto = false
                statusMessage = "Photos permission is needed to save this image."
                return
            }

            do {
                try await savePhotoData(pendingPhotoData)
                isSavingPhoto = false
                statusMessage = "Photo saved to Photos."
            } catch {
                isSavingPhoto = false
                statusMessage = "Could not save photo. Please try again."
            }
        }
    }

    func resetCapture() {
        pendingPhotoData = nil
        capturedImageData = nil
        clearRecognition()
        statusMessage = "AI recognition is not available yet."
    }

    private func requestPhotoLibraryAddPermission() async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch currentStatus {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func savePhotoData(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private func clearRecognition() {
        recognizedProduct = nil
        isRecognizing = false
    }
}
