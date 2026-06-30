@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onFocus: (_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void
    let onZoom: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        context.coordinator.previewView = view
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFocus: onFocus, onZoom: onZoom)
    }

    final class Coordinator: NSObject {
        let onFocus: (_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void
        let onZoom: (CGFloat) -> Void
        weak var previewView: PreviewUIView?
        private var baseZoomFactor: CGFloat = 1

        init(
            onFocus: @escaping (_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void,
            onZoom: @escaping (CGFloat) -> Void
        ) {
            self.onFocus = onFocus
            self.onZoom = onZoom
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let previewView else {
                return
            }

            let viewPoint = gesture.location(in: previewView)
            let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            onFocus(devicePoint, viewPoint)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                baseZoomFactor = max(baseZoomFactor, 1)
            case .changed:
                onZoom(baseZoomFactor * gesture.scale)
            case .ended, .cancelled, .failed:
                baseZoomFactor = max(baseZoomFactor * gesture.scale, 1)
            default:
                break
            }
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
