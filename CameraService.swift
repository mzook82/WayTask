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
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoCaptureCompletion: ((Result<CapturedPhoto, Error>) -> Void)?

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

            self.photoOutput.capturePhoto(with: settings, delegate: self)
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

        if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            try videoDevice.lockForConfiguration()
            videoDevice.focusMode = .continuousAutoFocus
            videoDevice.unlockForConfiguration()
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async { [weak self] in
                self?.photoCaptureCompletion?(.failure(error))
                self?.photoCaptureCompletion = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { [weak self] in
                self?.photoCaptureCompletion?(.failure(CameraServiceError.captureFailed))
                self?.photoCaptureCompletion = nil
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.photoCaptureCompletion?(.success(CapturedPhoto(data: data)))
            self?.photoCaptureCompletion = nil
        }
    }
}
