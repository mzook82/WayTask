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

    enum RecognitionPhase: String {
        case idle
        case captured
        case analyzing
        case result
        case confirmation
        case unavailable
        case failed
    }

    @Published var selectedMode: Mode = .photo
    @Published var pendingPhotoData: Data?
    @Published var capturedImageData: Data?
    @Published var recognitionResult: RecognitionResult?
    @Published var selectedCandidate: ProductCandidate?
    @Published var confirmedCandidate: ProductCandidate?
    @Published var recognitionPhase: RecognitionPhase = .idle
    @Published var isRecognizing = false
    @Published var isSavingPhoto = false
    @Published var statusMessage = "AI recognition is not available yet."
    @Published var focusPoint: CGPoint?

    let cameraService: CameraService

    private let recognitionService: ProductRecognitionServicing
    private var pendingPhotoSource: RecognitionInputSource = .cameraCapture

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

    var recognizedProduct: ProductCandidate? {
        confirmedCandidate
    }

    var canAddProduct: Bool {
        confirmedCandidate != nil
    }

    var canConfirmCandidate: Bool {
        selectedCandidate != nil && confirmedCandidate == nil
    }

    var isShowingPhotoPreview: Bool {
        pendingPhotoData != nil
    }

    var shoppingContext: ShoppingContext? {
        guard let confirmedCandidate else {
            return nil
        }

        return ShoppingContext(
            activeShoppingListItems: [
                ShoppingContextItem(
                    id: confirmedCandidate.id,
                    name: confirmedCandidate.name,
                    productHints: confirmedCandidate.productHints
                )
            ],
            availableProductHints: confirmedCandidate.productHints
        )
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
        pendingPhotoSource = .cameraCapture
        recognitionPhase = .captured
        statusMessage = "Taking photo..."

        cameraService.capturePhoto { [weak self] result in
            guard let self else {
                return
            }

            Task { @MainActor in
                switch result {
                case .success(let photo):
                    self.pendingPhotoData = photo.data
                    self.recognitionPhase = .captured
                    self.statusMessage = "Review your photo before using it."
                case .failure:
                    self.recognitionPhase = .failed
                    self.statusMessage = "Photo capture failed. Please try again."
                }
            }
        }
    }

    func handleSelectedPhotoData(_ data: Data?) {
        clearRecognition()
        pendingPhotoData = nil
        pendingPhotoSource = .photoLibrary

        guard let data else {
            recognitionPhase = .failed
            statusMessage = "We could not load that photo. Please choose another one."
            return
        }

        pendingPhotoData = data
        recognitionPhase = .captured
        statusMessage = "Review your photo before using it."
    }

    func usePendingPhoto() {
        guard let pendingPhotoData else {
            return
        }

        capturedImageData = pendingPhotoData
        self.pendingPhotoData = nil
        clearRecognition()
        analyzeCapturedPhoto(pendingPhotoData, inputSource: pendingPhotoSource)
    }

    func confirmSelectedCandidate() {
        guard let selectedCandidate else {
            return
        }

        confirmedCandidate = selectedCandidate
        recognitionPhase = .confirmation
        statusMessage = "Product confirmed and ready for your shopping context."
    }

    func retakePhoto() {
        pendingPhotoData = nil
        capturedImageData = nil
        pendingPhotoSource = .cameraCapture
        clearRecognition()
        recognitionPhase = .idle
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
        pendingPhotoSource = .cameraCapture
        clearRecognition()
        recognitionPhase = .idle
        statusMessage = "AI recognition is not available yet."
    }

    private func analyzeCapturedPhoto(_ imageData: Data, inputSource: RecognitionInputSource) {
        recognitionPhase = .analyzing
        isRecognizing = true
        statusMessage = "Analyzing photo..."

        Task {
            let result = await recognitionService.analyzeProduct(from: imageData, inputSource: inputSource)
            recognitionResult = result
            selectedCandidate = result.bestCandidate
            confirmedCandidate = nil
            isRecognizing = false

            if let selectedCandidate {
                recognitionPhase = .result
                statusMessage = "Review \(selectedCandidate.name) before adding it."
            } else {
                recognitionPhase = result.status == .failed ? .failed : .unavailable
                statusMessage = result.message
            }
        }
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
        recognitionResult = nil
        selectedCandidate = nil
        confirmedCandidate = nil
        isRecognizing = false
    }
}
