import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CameraView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appStateManager: AppStateManager

    @StateObject private var viewModel = CameraViewModel()
    private let shoppingListService = ShoppingListService()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var focusIndicatorPoint: CGPoint?
    @State private var focusIndicatorScale = 1.35
    @State private var focusIndicatorOpacity = 0.0
    @State private var manualProductName = ""
    @State private var manualProductBrand = ""
    @State private var manualProductCategory = ""

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

            if let previewData = viewModel.pendingPhotoData {
                capturedPhotoPreview(previewData)
            } else {
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
            }

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

    private func capturedPhotoPreview(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(WayTaskDesign.accent)

                    Text("Photo preview unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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

    private var isShowingBarcodeResult: Bool {
        viewModel.barcodeResult != nil || viewModel.confirmedBarcodeResult != nil
    }

    private var displayedProduct: ProductCandidate? {
        viewModel.recognizedProduct ?? viewModel.selectedCandidate
    }

    private var currentBarcodeResult: BarcodeResult? {
        viewModel.confirmedBarcodeResult ?? viewModel.barcodeResult
    }

    private var isShowingProductResult: Bool {
        displayedProduct != nil
    }

    private var actionPanel: some View {
        VStack(spacing: isShowingBarcodeResult || isShowingProductResult ? 10 : 16) {
            if let product = displayedProduct {
                recognizedProductCard(product)
                productResultControls(product)
            } else {
                if let barcode = viewModel.barcodeResult ?? viewModel.confirmedBarcodeResult {
                    barcodeResultCard(barcode)
                }

                if viewModel.isShowingPhotoPreview {
                    photoReviewControls
                } else {
                    captureControls
                }

                if viewModel.barcodeResult != nil || viewModel.confirmedBarcodeResult != nil {
                    barcodeControls
                }

                if viewModel.selectedMode != .barcode {
                    aiUnavailableMessage
                }
            }
        }
        .padding(.horizontal, isShowingBarcodeResult || isShowingProductResult ? 16 : 20)
        .padding(.top, isShowingBarcodeResult || isShowingProductResult ? 12 : 20)
        .padding(.bottom, isShowingBarcodeResult || isShowingProductResult ? 16 : 20)
        .background(.black.opacity(0.42))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WayTaskDesign.surfaceBorder)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var captureControls: some View {
        if isShowingProductResult {
            EmptyView()
        } else if isShowingBarcodeResult {
            compactBarcodeCameraState
        } else {
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
        }
    }

    private var compactBarcodeCameraState: some View {
        HStack(spacing: 10) {
            Image(systemName: "barcode.viewfinder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 34, height: 34)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(viewModel.confirmedBarcodeResult == nil ? "Review barcode" : "Barcode confirmed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .wayTaskCard(cornerRadius: 14)
    }

    private var photoReviewControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    viewModel.usePendingPhoto()
                } label: {
                    Label("Use Photo", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 52, cornerRadius: 16, shadow: true))

                Button {
                    viewModel.retakePhoto()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 52, cornerRadius: 16))
            }

            Button {
                viewModel.savePendingPhotoToLibrary()
            } label: {
                if viewModel.isSavingPhoto {
                    ProgressView()
                        .tint(WayTaskDesign.accent)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 46, cornerRadius: 15))
            .disabled(viewModel.isSavingPhoto)
        }
    }

    private func productResultControls(_ product: ProductCandidate) -> some View {
        HStack(spacing: 12) {
            if viewModel.canAddProduct {
                Button {
                    addRecognizedProduct(product)
                } label: {
                    centeredCTAContent(title: "Add to Shopping List", systemName: "plus.circle.fill")
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 50, cornerRadius: 16, shadow: true))
            } else if viewModel.canConfirmCandidate {
                Button {
                    if product.source == .ai {
                        addRecognizedProduct(product)
                    } else {
                        viewModel.confirmSelectedCandidate()
                    }
                } label: {
                    centeredCTAContent(
                        title: product.source == .ai ? "Add to Shopping List" : "Use Product",
                        systemName: product.source == .ai ? "plus.circle.fill" : "checkmark.seal.fill"
                    )
                }
                .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 50, cornerRadius: 16, shadow: true))

                Button {
                    editSuggestedProduct(product)
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 50, cornerRadius: 16))
            }

            Button {
                scanAgain()
            } label: {
                Label("Scan Again", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 50, cornerRadius: 16))
        }
    }

    private func centeredCTAContent(title: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
            Text(title)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var barcodeControls: some View {
        VStack(spacing: 10) {
            if viewModel.canCreateProductFromBarcode {
                manualBarcodeProductForm
            }

            HStack(spacing: 12) {
                if viewModel.canConfirmBarcode {
                    Button {
                        viewModel.confirmBarcode()
                    } label: {
                        Label("Confirm", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 44, cornerRadius: 14, shadow: true))
                }

                Button {
                    scanAgain()
                } label: {
                    Label("Scan Again", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WayTaskSecondaryPillButtonStyle(minHeight: 44, cornerRadius: 14))
            }
        }
    }

    private var manualBarcodeProductForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add product details")
                    .font(.headline)
                    .foregroundStyle(WayTaskDesign.primaryText)

                Text("Open Food Facts did not return product details. Enter only what you know.")
                    .font(.caption)
                    .foregroundStyle(WayTaskDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                TextField("Product name", text: $manualProductName)
                    .textInputAutocapitalization(.words)
                    .wayTaskManualInputStyle()

                TextField("Brand optional", text: $manualProductBrand)
                    .textInputAutocapitalization(.words)
                    .wayTaskManualInputStyle()

                TextField("Category optional", text: $manualProductCategory)
                    .textInputAutocapitalization(.words)
                    .wayTaskManualInputStyle()
            }

            if let barcode = currentBarcodeResult {
                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .foregroundStyle(WayTaskDesign.accent)

                    Text("\(barcode.type.displayName): \(barcode.value)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Barcode \(barcode.value)")
            }

            Button {
                addManualBarcodeProductToShoppingList()
            } label: {
                centeredCTAContent(title: "Add Product", systemName: "plus.circle.fill")
            }
            .buttonStyle(WayTaskPrimaryPillButtonStyle(height: 46, cornerRadius: 15, shadow: true))
            .disabled(manualProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .wayTaskCard(cornerRadius: 16)
    }

    private var aiUnavailableMessage: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(WayTaskDesign.accent)

            Text(viewModel.selectedMode == .aiVision ? "Gemini can suggest product details from your photo." : "Photo recognition uses Gemini when available.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)

            Spacer(minLength: 0)
        }
        .padding(12)
        .wayTaskCard(cornerRadius: 14)
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

    private func barcodeResultCard(_ barcode: BarcodeResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "barcode.viewfinder")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WayTaskDesign.accent)
                .frame(width: 42, height: 42)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label("Barcode detected", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.accent)
                        .lineLimit(1)

                    Text(barcode.type.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WayTaskDesign.surfaceElevated)
                        .clipShape(Capsule())
                }

                Text(barcode.value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(WayTaskDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WayTaskDesign.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.24), lineWidth: 1)
        }
    }

    private func recognizedProductCard(_ product: ProductCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                WayTaskProductThumbnail(data: product.imageData ?? viewModel.capturedImageData, size: 76, cornerRadius: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Label(product.source == .ai ? "We think this is..." : "Product Found", systemImage: product.source == .ai ? "sparkles" : "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WayTaskDesign.accent)
                        .lineLimit(1)

                    Text(product.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(WayTaskDesign.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    productDetailLine(product)
                }

                Spacer(minLength: 0)
            }

            if let barcodeLine = barcodeDetailLine(for: product) {
                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.accent)

                    Text(barcodeLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WayTaskDesign.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(WayTaskDesign.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(WayTaskDesign.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WayTaskDesign.accent.opacity(0.24), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func productDetailLine(_ product: ProductCandidate) -> some View {
        let details = [product.brand, product.category]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if product.source == .ai {
            let confidenceText = product.confidence.map { "AI-suggested / \(Int(($0 * 100).rounded()))% confidence" } ?? "AI-suggested"
            let detailText = details.isEmpty ? confidenceText : "\(details.joined(separator: " / ")) / \(confidenceText)"
            Text(detailText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(2)
        } else if details.isEmpty {
            Text("Review and add this product.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(1)
        } else {
            Text(details.joined(separator: " / "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WayTaskDesign.secondaryText)
                .lineLimit(2)
        }
    }

    private func barcodeDetailLine(for product: ProductCandidate) -> String? {
        guard let barcode = product.barcode ?? currentBarcodeResult?.value else {
            return nil
        }

        let type = currentBarcodeResult?.type.displayName ?? "Barcode"
        return "\(type) / \(barcode)"
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

    private func scanAgain() {
        resetManualBarcodeForm()
        viewModel.scanAgain()
    }

    private func editSuggestedProduct(_ product: ProductCandidate) {
        manualProductName = product.name
        manualProductBrand = product.brand ?? ""
        manualProductCategory = product.category ?? ""
        viewModel.useCandidateForManualEditing()
    }

    private func addManualBarcodeProductToShoppingList() {
        let name = manualProductName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty,
              let barcode = currentBarcodeResult else {
            return
        }

        let brand = manualProductBrand.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = manualProductCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let product = ProductCandidate(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            category: category.isEmpty ? nil : category,
            source: .barcode,
            productHints: [name, brand, category, barcode.value, barcode.type.displayName].filter { !$0.isEmpty },
            barcode: barcode.value
        )

        addRecognizedProduct(product)
        resetManualBarcodeForm()
    }

    private func resetManualBarcodeForm() {
        manualProductName = ""
        manualProductBrand = ""
        manualProductCategory = ""
    }

    private func addRecognizedProduct(_ product: ProductCandidate) {
        do {
            let item = try shoppingListService.addRecognizedProduct(
                product,
                fallbackImageData: viewModel.capturedImageData,
                in: modelContext
            )
            appStateManager.shoppingListDidChange(revealing: item.id)
            viewModel.productWasAddedToShoppingList(product)
            appStateManager.selectedTab = .products
        } catch {
            viewModel.productAddFailed(error)
        }
    }
}

private struct WayTaskManualInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WayTaskDesign.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WayTaskDesign.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(WayTaskDesign.surfaceBorder, lineWidth: 1)
            }
    }
}

private extension View {
    func wayTaskManualInputStyle() -> some View {
        modifier(WayTaskManualInputStyle())
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
