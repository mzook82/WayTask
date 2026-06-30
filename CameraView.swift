import PhotosUI
import SwiftData
import SwiftUI

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager

    @StateObject private var viewModel = CameraViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var focusIndicatorPoint: CGPoint?
    @State private var focusIndicatorScale = 1.35
    @State private var focusIndicatorOpacity = 0.0

    var body: some View {
        NavigationStack {
            ZStack {
                WayTaskDesign.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    cameraSurface
                    actionPanel
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        appStateManager.selectedTab = .products
                    }
                    .tint(WayTaskDesign.accent)
                }
            }
            .onAppear {
                viewModel.startCamera()
            }
            .onDisappear {
                viewModel.stopCamera()
            }
            .onChange(of: selectedPhotoItem) {
                loadSelectedPhoto()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        WayTaskScreenHeader(
            title: "Scan & Identify",
            subtitle: "Live camera preview with photo capture"
        )
        .overlay(alignment: .trailing) {
            WayTaskIconButton(systemName: viewModel.cameraService.isFlashOn ? "bolt.fill" : "bolt.slash.fill") {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
                    viewModel.toggleFlash()
                }
            }
            .symbolEffect(.bounce, value: viewModel.cameraService.isFlashOn)
            .opacity(viewModel.cameraService.supportsFlash ? 1 : 0.4)
            .disabled(!viewModel.cameraService.supportsFlash)
            .accessibilityLabel(viewModel.cameraService.isFlashOn ? "Turn flash off" : "Turn flash on")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var cameraSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(WayTaskDesign.scannerSurface)

            CameraPreviewView(
                session: viewModel.cameraService.session,
                onFocus: { devicePoint, viewPoint in
                    viewModel.focus(at: devicePoint)
                    showFocusIndicator(at: viewPoint)
                },
                onZoom: { zoomFactor in
                    viewModel.zoom(to: zoomFactor)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .opacity(viewModel.cameraService.authorizationStatus == .authorized ? 1 : 0)

            cameraOverlay
            focusIndicator
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
        }
        .padding(.horizontal, 22)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var focusIndicator: some View {
        if let focusIndicatorPoint {
            FocusIndicator()
                .scaleEffect(focusIndicatorScale)
                .opacity(focusIndicatorOpacity)
                .position(focusIndicatorPoint)
                .allowsHitTesting(false)
        }
    }

    private var cameraOverlay: some View {
        ZStack {
            if viewModel.cameraService.authorizationStatus != .authorized {
                unavailableState
            } else {
                scanFrame

                VStack {
                    modePicker
                    Spacer()
                    statusBanner
                }
                .padding(18)
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(WayTaskDesign.accent)

            Text("Camera Access Needed")
                .font(.headline)
                .foregroundStyle(WayTaskDesign.primaryText)

            Text("Allow camera access in Settings to scan and photograph products.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(WayTaskDesign.secondaryText)
        }
        .padding(28)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(CameraViewModel.Mode.allCases) { mode in
                WayTaskFilterChip(
                    title: mode.title,
                    isSelected: viewModel.selectedMode == mode
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.selectedMode = mode
                        viewModel.resetCapture()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
                .frame(width: 238, height: 238)

            ScannerCorner(alignment: .topLeading)
            ScannerCorner(alignment: .topTrailing)
            ScannerCorner(alignment: .bottomLeading)
            ScannerCorner(alignment: .bottomTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            if viewModel.isRecognizing {
                ProgressView()
                    .tint(WayTaskDesign.accent)
            } else {
                Image(systemName: statusIconName)
                    .foregroundStyle(WayTaskDesign.accent)
            }

            Text(viewModel.statusMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.primaryText)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
        }
    }

    private var actionPanel: some View {
        VStack(spacing: 16) {
            if let product = viewModel.recognizedProduct {
                recognizedProductCard(product)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    WayTaskModeTile(title: "Library", systemName: "photo")
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.34), lineWidth: 4)
                            .frame(width: 70, height: 70)

                        Circle()
                            .fill(WayTaskDesign.accentGradient)
                            .frame(width: 56, height: 56)
                            .shadow(color: WayTaskDesign.accent.opacity(0.36), radius: 18, y: 8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take photo")

                WayTaskModeTile(title: viewModel.selectedMode.title, systemName: viewModel.selectedMode.iconName)
            }

            if viewModel.canAddProduct,
               let product = viewModel.recognizedProduct {
                Button {
                    addRecognizedProduct(product)
                } label: {
                    Label("Add to List", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 56, cornerRadius: 18, shadow: true))
            }
        }
        .padding(20)
        .background(.black.opacity(0.42))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WayTaskDesign.surfaceBorder)
                .frame(height: 1)
        }
    }

    private var statusIconName: String {
        if viewModel.recognizedProduct != nil {
            return "checkmark.seal.fill"
        }

        switch viewModel.selectedMode {
        case .photo:
            return "camera"
        case .barcode:
            return "barcode.viewfinder"
        case .aiVision:
            return "sparkles"
        }
    }

    private func recognizedProductCard(_ product: ProductRecognitionResult) -> some View {
        HStack(spacing: 12) {
            WayTaskProductThumbnail(data: viewModel.capturedImageData, size: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(product.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)

                Label("Product recognized", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WayTaskDesign.accent)
            }

            Spacer()
        }
        .padding(14)
        .background(WayTaskDesign.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.24), lineWidth: 1)
        }
    }

    private func showFocusIndicator(at point: CGPoint) {
        focusIndicatorPoint = point
        focusIndicatorScale = 1.35
        focusIndicatorOpacity = 0

        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            focusIndicatorScale = 1
            focusIndicatorOpacity = 1
        }

        Task {
            try? await Task.sleep(for: .milliseconds(650))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    focusIndicatorOpacity = 0
                }
            }
        }
    }

    private func loadSelectedPhoto() {
        Task {
            let data = try? await selectedPhotoItem?.loadTransferable(type: Data.self)
            viewModel.handleSelectedPhotoData(data)
            selectedPhotoItem = nil
        }
    }

    private func addRecognizedProduct(_ product: ProductRecognitionResult) {
        let item = ShoppingItem(
            name: product.name,
            imageData: viewModel.capturedImageData
        )

        modelContext.insert(item)
        try? modelContext.save()
        viewModel.resetCapture()
        appStateManager.selectedTab = .products
    }
}

private struct FocusIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(WayTaskDesign.accent, lineWidth: 2)
            .frame(width: 68, height: 68)
            .overlay {
                Circle()
                    .fill(WayTaskDesign.accent)
                    .frame(width: 6, height: 6)
            }
            .shadow(color: WayTaskDesign.accent.opacity(0.45), radius: 8)
    }
}

private struct ScannerCorner: View {
    let alignment: Alignment

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .trim(from: 0, to: 0.34)
            .stroke(WayTaskDesign.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: 58, height: 58)
            .rotationEffect(rotation)
            .frame(width: 238, height: 238, alignment: alignment)
    }

    private var rotation: Angle {
        switch alignment {
        case .topLeading:
            return .degrees(180)
        case .topTrailing:
            return .degrees(270)
        case .bottomLeading:
            return .degrees(90)
        default:
            return .degrees(0)
        }
    }
}
