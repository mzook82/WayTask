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
        case barcodeDetected
        case result
        case confirmation
        case unavailable
        case failed
    }

    @Published var selectedMode: Mode = .photo {
        didSet {
            guard oldValue != selectedMode else {
                return
            }

            configureMode()
        }
    }
    @Published var pendingPhotoData: Data?
    @Published var capturedImageData: Data?
    @Published var recognitionResult: RecognitionResult?
    @Published var selectedCandidate: ProductCandidate?
    @Published var confirmedCandidate: ProductCandidate?
    @Published var barcodeResult: BarcodeResult?
    @Published var confirmedBarcodeResult: BarcodeResult?
    @Published var isWaitingForBarcodePackagePhoto = false
    @Published var recognitionPhase: RecognitionPhase = .idle
    @Published private(set) var latestShoppingContext: ShoppingContext?
    @Published var isRecognizing = false
    @Published var isSavingPhoto = false
    @Published var statusMessage = "Ready to capture a photo."
    @Published var focusPoint: CGPoint?

    let cameraService: CameraService

    private let recognitionService: ProductRecognitionServicing
    private let productDataProvider: any ProductDataProvider
    private let aiRecognitionService: AIProductRecognitionServicing
    private var pendingPhotoSource: RecognitionInputSource = .cameraCapture
    private var recognitionTask: Task<Void, Never>?

    init() {
        self.cameraService = CameraService()
        self.recognitionService = ProductRecognitionService()
        self.productDataProvider = OpenFoodFactsProvider()
        self.aiRecognitionService = GeminiProductRecognitionService()
    }

    init(
        cameraService: CameraService,
        recognitionService: ProductRecognitionServicing,
        productDataProvider: any ProductDataProvider,
        aiRecognitionService: AIProductRecognitionServicing
    ) {
        self.cameraService = cameraService
        self.recognitionService = recognitionService
        self.productDataProvider = productDataProvider
        self.aiRecognitionService = aiRecognitionService
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

    var canConfirmBarcode: Bool {
        barcodeResult != nil && confirmedBarcodeResult == nil
    }

    var canCreateProductFromBarcode: Bool {
        guard confirmedBarcodeResult != nil,
              selectedCandidate == nil,
              confirmedCandidate == nil,
              !isWaitingForBarcodePackagePhoto,
              !isRecognizing else {
            return false
        }

        return recognitionResult?.status == .noMatch || recognitionResult?.status == .failed || recognitionResult?.status == .unavailable
    }


    var isShowingPhotoPreview: Bool {
        pendingPhotoData != nil
    }

    var shoppingContext: ShoppingContext? {
        if let confirmedCandidate {
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

        if let confirmedBarcodeResult {
            return ShoppingContext(
                selectedInterests: [confirmedBarcodeResult.type.displayName],
                recentSearches: [confirmedBarcodeResult.value],
                availableProductHints: [confirmedBarcodeResult.value, confirmedBarcodeResult.type.rawValue]
            )
        }

        return nil
    }

    func startCamera() {
        cameraService.requestAccessAndConfigure()
        configureMode()
    }

    func stopCamera() {
        recognitionTask?.cancel()
        recognitionTask = nil
        cameraService.stopBarcodeScanning()
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
        recognitionTask?.cancel()
        recognitionTask = nil
        if !isWaitingForBarcodePackagePhoto {
            clearRecognition()
        }
        pendingPhotoData = nil
        pendingPhotoSource = .cameraCapture
        recognitionPhase = .captured
        statusMessage = isWaitingForBarcodePackagePhoto ? "Capturing product package..." : "Taking photo..."

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
        if !isWaitingForBarcodePackagePhoto {
            clearRecognition()
        }
        pendingPhotoData = nil
        pendingPhotoSource = .photoLibrary

        guard let data else {
            recognitionPhase = .failed
            statusMessage = "We could not load that photo. Please choose another one."
            return
        }

        pendingPhotoData = data
        recognitionPhase = .captured
        statusMessage = isWaitingForBarcodePackagePhoto ? "Use this package photo for AI analysis." : "Review your photo before using it."
    }

    func usePendingPhoto() {
        guard let pendingPhotoData, !isRecognizing else {
            return
        }

        capturedImageData = pendingPhotoData
        self.pendingPhotoData = nil

        if selectedMode == .barcode, let barcode = confirmedBarcodeResult, isWaitingForBarcodePackagePhoto {
            isWaitingForBarcodePackagePhoto = false
            analyzeAIProductFallback(for: barcode, imageData: pendingPhotoData)
        } else {
            clearRecognition()

            if selectedMode == .aiVision {
                analyzeAIProductPhoto(pendingPhotoData)
            } else {
                analyzeCapturedPhoto(pendingPhotoData, inputSource: pendingPhotoSource)
            }
        }
    }

    func confirmSelectedCandidate() {
        guard let selectedCandidate else {
            return
        }

        confirmedCandidate = selectedCandidate
        recognitionPhase = .confirmation
        statusMessage = "Product confirmed and ready for your shopping context."
    }

    func confirmBarcode() {
        guard let barcodeResult, !isRecognizing else {
            return
        }

        confirmedBarcodeResult = barcodeResult
        lookupProduct(for: barcodeResult)
    }

    func productAddFailed(_ error: Error? = nil) {
        recognitionPhase = .failed
        statusMessage = "Could not add this product. Please try again."
    }

    func productWasAddedToShoppingList(_ candidate: ProductCandidate) {
        latestShoppingContext = ShoppingContext(
            activeShoppingListItems: [
                ShoppingContextItem(
                    id: candidate.id,
                    name: candidate.name,
                    productHints: candidate.productHints
                )
            ],
            recentSearches: [candidate.barcode].compactMap { $0 },
            availableProductHints: candidate.productHints + [candidate.barcode].compactMap { $0 }
        )

        pendingPhotoData = nil
        capturedImageData = nil
        pendingPhotoSource = .cameraCapture
        clearRecognition()
        recognitionPhase = .idle
        statusMessage = "Added to your Shopping List"

        if selectedMode == .barcode {
            startBarcodeScanning()
        }
    }

    func scanAgain() {
        recognitionTask?.cancel()
        recognitionTask = nil
        pendingPhotoData = nil
        capturedImageData = nil
        pendingPhotoSource = .cameraCapture
        barcodeResult = nil
        confirmedBarcodeResult = nil
        isWaitingForBarcodePackagePhoto = false
        recognitionResult = nil
        selectedCandidate = nil
        confirmedCandidate = nil
        recognitionPhase = .idle
        statusMessage = "Point the camera at a barcode."
        if selectedMode == .barcode {
            startBarcodeScanning()
        }
    }

    func retakePhoto() {
        pendingPhotoData = nil
        capturedImageData = nil
        pendingPhotoSource = .cameraCapture
        if !isWaitingForBarcodePackagePhoto {
            clearRecognition()
        }
        recognitionPhase = isWaitingForBarcodePackagePhoto ? .unavailable : .idle
        statusMessage = isWaitingForBarcodePackagePhoto ? "Product not found. Show the front of the package." : selectedMode == .aiVision ? "Capture a product photo for Gemini." : "Ready to capture a photo."
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
        isWaitingForBarcodePackagePhoto = false
        recognitionPhase = .idle
        statusMessage = selectedMode == .barcode
            ? "Point the camera at a barcode."
            : selectedMode == .aiVision
                ? "Capture a product photo for Gemini."
                : "Ready to capture a photo."
    }

    private func configureMode() {
        clearRecognition()
        pendingPhotoData = nil
        capturedImageData = nil

        if selectedMode == .barcode {
            statusMessage = "Point the camera at a barcode."
            startBarcodeScanning()
        } else {
            cameraService.stopBarcodeScanning()
            statusMessage = selectedMode == .aiVision
                ? "Capture a product photo for Gemini."
                : "Ready to capture a photo."
        }
    }

    private func startBarcodeScanning() {
        cameraService.startBarcodeScanning { [weak self] result in
            Task { @MainActor in
                self?.handleBarcodeDetection(result)
            }
        }
    }

    private func lookupProduct(for barcode: BarcodeResult) {
        recognitionPhase = .analyzing
        isRecognizing = true
        isWaitingForBarcodePackagePhoto = false
        statusMessage = "Searching product database..."

        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let candidates = try await productDataProvider.products(
                    for: ProductDataRequest(barcode: barcode.value)
                )
                guard !Task.isCancelled else {
                    return
                }
                isRecognizing = false

                guard let candidate = candidates.first else {
                    requestPackagePhotoForAIFallback(
                        barcode: barcode,
                        message: "Product not found. Show the front of the package."
                    )
                    return
                }

                recognitionResult = RecognitionResult(
                    status: .recognized,
                    candidates: candidates,
                    message: "Product found.",
                    inputSource: .barcode
                )
                selectedCandidate = candidate
                confirmedCandidate = nil
                recognitionPhase = .result
                statusMessage = "Review and add this product."
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                requestPackagePhotoForAIFallback(
                    barcode: barcode,
                    message: "Product lookup failed. Show the front of the package."
                )
            }
        }
    }

    private func requestPackagePhotoForAIFallback(barcode: BarcodeResult, message: String) {
        recognitionResult = RecognitionResult(
            status: .noMatch,
            candidates: [],
            message: message,
            inputSource: .barcode
        )
        confirmedBarcodeResult = barcode
        selectedCandidate = nil
        confirmedCandidate = nil
        capturedImageData = nil
        pendingPhotoData = nil
        isRecognizing = false
        isWaitingForBarcodePackagePhoto = true
        recognitionPhase = .unavailable
        statusMessage = message
    }

    private func analyzeAIProductPhoto(_ imageData: Data) {
        recognitionPhase = .analyzing
        isRecognizing = true
        statusMessage = "Analyzing product with AI..."

        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let result = await aiRecognitionService.suggestProduct(from: imageData, barcode: nil)
            await applyAIRecognitionResult(result)
        }
    }

    private func analyzeAIProductFallback(for barcode: BarcodeResult, imageData: Data) {
        recognitionPhase = .analyzing
        isRecognizing = true
        statusMessage = "Analyzing product with AI..."

        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self else {
                return
            }

            let result = await aiRecognitionService.suggestProduct(
                from: imageData,
                barcode: barcode
            )

            await applyAIRecognitionResult(result)
        }
    }

    private func applyAIRecognitionResult(_ result: RecognitionResult) async {
        guard !Task.isCancelled else {
            return
        }

        recognitionResult = result
        isRecognizing = false

        guard let candidate = result.bestCandidate,
              (candidate.confidence ?? 0) >= 0.55 else {
            selectedCandidate = nil
            confirmedCandidate = nil
            recognitionPhase = .unavailable
            statusMessage = result.message
            return
        }

        selectedCandidate = candidate
        confirmedCandidate = nil
        recognitionPhase = .result
        statusMessage = "We think this is \(candidate.name). Review before adding."
    }

    func useCandidateForManualEditing() {
        selectedCandidate = nil
        confirmedCandidate = nil
        recognitionPhase = .unavailable
        statusMessage = "Edit the suggested details before adding."
    }

    private func productLookupMessage(for error: Error) -> String {
        guard let providerError = error as? DataProviderError else {
            return "Product lookup is unavailable right now."
        }

        switch providerError {
        case .invalidRequest:
            return "This barcode could not be used for lookup."
        case .networkUnavailable:
            return "No internet connection. Try again when you're online."
        case .timeout:
            return "Product lookup timed out. Please try again."
        case .unavailable:
            return "The product database is unavailable right now."
        case .unsupportedSource:
            return "This product database is not supported yet."
        }
    }

    private func handleBarcodeDetection(_ result: BarcodeResult) {
        guard selectedMode == .barcode,
              confirmedBarcodeResult == nil else {
            return
        }

        barcodeResult = result
        recognitionPhase = .barcodeDetected
        statusMessage = "Barcode detected"
        recognitionResult = RecognitionResult(
            status: .recognized,
            candidates: [],
            message: "Barcode detected",
            inputSource: .barcode
        )
        cameraService.stopBarcodeScanning()
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
        barcodeResult = nil
        confirmedBarcodeResult = nil
        isWaitingForBarcodePackagePhoto = false
        isRecognizing = false
    }
}
