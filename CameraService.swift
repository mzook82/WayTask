@preconcurrency import AVFoundation
import Combine
import UIKit

struct CapturedPhoto {
    let data: Data
}

enum CameraServiceError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required to scan products."
        case .deviceUnavailable:
            return "No camera is available on this device."
        case .configurationFailed:
            return "The camera could not be configured."
        case .captureFailed:
            return "The photo could not be captured."
        }
    }
}

final class CameraService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isFlashOn = false
    @Published private(set) var currentZoomFactor: CGFloat = 1
    @Published private(set) var statusMessage = "AI product recognition is not available yet."

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "WayTask.CameraService.SessionQueue")
    private let metadataQueue = DispatchQueue(label: "WayTask.CameraService.MetadataQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoCaptureCompletion: ((Result<CapturedPhoto, Error>) -> Void)?
    private var activePhotoCaptureProcessors: [CameraPhotoCaptureProcessor] = []
    private var barcodeHandler: ((BarcodeResult) -> Void)?
    private var lastBarcodeValue: String?
    private var lastBarcodeDate: Date?
    private var isBarcodeScanningEnabled = false

    var supportsFlash: Bool {
        videoDeviceInput?.device.hasTorch == true
    }

    func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationStatus = .authorized
            configureSessionIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.configureSessionIfNeeded()
                    }
                }
            }
        default:
            authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else {
                return
            }

            self.session.startRunning()

            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                return
            }

            self.session.stopRunning()

            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    func startBarcodeScanning(onDetected: @escaping (BarcodeResult) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else {
                return
            }

            self.barcodeHandler = onDetected
            self.isBarcodeScanningEnabled = true
            self.configureBarcodeTypesIfAvailable()
        }
    }

    func stopBarcodeScanning() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.isBarcodeScanningEnabled = false
            self.barcodeHandler = nil
            self.lastBarcodeValue = nil
            self.lastBarcodeDate = nil
            if self.isConfigured {
                self.metadataOutput.metadataObjectTypes = []
            }
        }
    }

    func capturePhoto(completion: @escaping (Result<CapturedPhoto, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured else {
                DispatchQueue.main.async {
                    completion(.failure(CameraServiceError.configurationFailed))
                }
                return
            }

            self.photoCaptureCompletion = completion

            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(.on), self.isFlashOn {
                settings.flashMode = .on
            }

            let processor = CameraPhotoCaptureProcessor { [weak self] result, processor in
                DispatchQueue.main.async {
                    self?.photoCaptureCompletion?(result)
                    self?.photoCaptureCompletion = nil
                    self?.activePhotoCaptureProcessors.removeAll { $0 === processor }
                }
            }
            self.activePhotoCaptureProcessors.append(processor)
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    func toggleFlash() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.videoDeviceInput?.device,
                  device.hasTorch else {
                return
            }

            do {
                try device.lockForConfiguration()
                let shouldTurnOn = device.torchMode != .on
                device.torchMode = shouldTurnOn ? .on : .off
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.isFlashOn = shouldTurnOn
                }
            } catch {
                device.unlockForConfiguration()
            }
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDeviceInput?.device else {
                return
            }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = device.isFocusModeSupported(.autoFocus) ? .autoFocus : .continuousAutoFocus
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = device.isExposureModeSupported(.continuousAutoExposure) ? .continuousAutoExposure : .autoExpose
                }

                device.unlockForConfiguration()
            } catch {
                device.unlockForConfiguration()
            }
        }
    }

    func setZoomFactor(_ zoomFactor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.videoDeviceInput?.device else {
                return
            }

            do {
                try device.lockForConfiguration()
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
                let clampedZoom = min(max(zoomFactor, 1), maxZoom)
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.currentZoomFactor = clampedZoom
                }
            } catch {
                device.unlockForConfiguration()
            }
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else {
            start()
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                try self.configureSession()

                DispatchQueue.main.async {
                    self.isConfigured = true
                    self.start()
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraServiceError.deviceUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            throw CameraServiceError.configurationFailed
        }
        session.addInput(videoInput)
        videoDeviceInput = videoInput

        guard session.canAddOutput(photoOutput) else {
            throw CameraServiceError.configurationFailed
        }
        session.addOutput(photoOutput)

        guard session.canAddOutput(metadataOutput) else {
            throw CameraServiceError.configurationFailed
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
        configureBarcodeTypesIfAvailable()

        if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            try videoDevice.lockForConfiguration()
            videoDevice.focusMode = .continuousAutoFocus
            videoDevice.unlockForConfiguration()
        }
    }

    private func configureBarcodeTypesIfAvailable() {
        guard isConfigured || session.outputs.contains(metadataOutput) else {
            return
        }

        let supportedTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .qr]
        let availableTypes = metadataOutput.availableMetadataObjectTypes
        let enabledTypes = supportedTypes.filter { availableTypes.contains($0) }
        metadataOutput.metadataObjectTypes = isBarcodeScanningEnabled ? enabledTypes : []
    }

    private func barcodeType(from metadataType: AVMetadataObject.ObjectType, value: String) -> BarcodeType {
        switch metadataType {
        case .ean13:
            return value.hasPrefix("0") && value.count == 13 ? .upcA : .ean13
        case .ean8:
            return .ean8
        case .upce:
            return .upcE
        case .qr:
            return .qr
        default:
            return .unknown
        }
    }

    private func shouldEmitBarcode(value: String, now: Date) -> Bool {
        guard lastBarcodeValue == value,
              let lastBarcodeDate else {
            lastBarcodeValue = value
            lastBarcodeDate = now
            return true
        }

        if now.timeIntervalSince(lastBarcodeDate) > 1.5 {
            self.lastBarcodeDate = now
            return true
        }

        return false
    }
}

nonisolated private final class CameraPhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<CapturedPhoto, Error>, CameraPhotoCaptureProcessor) -> Void

    init(completion: @escaping (Result<CapturedPhoto, Error>, CameraPhotoCaptureProcessor) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error), self)
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraServiceError.captureFailed), self)
            return
        }

        completion(.success(CapturedPhoto(data: data)), self)
    }
}

extension CameraService: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard isBarcodeScanningEnabled,
              let codeObject = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = codeObject.stringValue,
              !value.isEmpty else {
            return
        }

        let now = Date()
        guard shouldEmitBarcode(value: value, now: now) else {
            return
        }

        let result = BarcodeResult(
            value: value,
            type: barcodeType(from: codeObject.type, value: value),
            scannedAt: now,
            confidence: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.barcodeHandler?(result)
        }
    }
}
