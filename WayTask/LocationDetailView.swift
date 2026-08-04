import SwiftUI
import SwiftData
import PhotosUI

// MARK: - T-18 target saved-location presentation

struct ProductStateLocationDetailProjectionPresentation: Equatable {
    let locationID: UUID
    let listID: ProductStateListID
    let listRevision: ProductStateListRevision
    let title: String
    let note: String?
    let coordinate: ShoppingCoordinate?
    let links: [ProductStateMapSavedLocationLinkPresentation]
    let issues: [ProductStateMapSavedLocationIssue]
    let metadata: ProductStateProjectionMetadata
}

enum ProductStateLocationDetailProjectionContent: Equatable {
    case idle
    case available(ProductStateLocationDetailProjectionPresentation)
    case stale(
        ProductStateLocationDetailProjectionPresentation,
        ProductStateMapStalenessPresentation
    )
    case unavailable(ProductStateProjectionMetadata)
    case invalid(ProductStateMapProjectionInvalidReason)
    case notFound(UUID)
}

enum ProductStateLocationDetailProjectionConsumer {
    static func make(
        locationID: UUID,
        mapState: ProductStateMapProjectionConsumerState
    ) -> ProductStateLocationDetailProjectionContent {
        switch mapState.content {
        case .idle:
            return .idle
        case let .unavailable(value):
            return .unavailable(value.metadata)
        case let .invalid(reason):
            return .invalid(reason)
        case let .available(map):
            return detail(
                locationID: locationID,
                map: map,
                staleness: nil
            )
        case let .stale(map, staleness):
            return detail(
                locationID: locationID,
                map: map,
                staleness: staleness
            )
        }
    }

    private static func detail(
        locationID: UUID,
        map: ProductStateMapProjectionPresentation,
        staleness: ProductStateMapStalenessPresentation?
    ) -> ProductStateLocationDetailProjectionContent {
        if let location = map.savedLocations.first(where: {
            $0.id == locationID
        }) {
            let presentation =
                ProductStateLocationDetailProjectionPresentation(
                    locationID: location.id,
                    listID: map.listID,
                    listRevision: map.listRevision,
                    title: location.title,
                    note: location.note,
                    coordinate: location.coordinate,
                    links: location.links,
                    issues: location.issues,
                    metadata: location.metadata
                )
            if let staleness {
                return .stale(presentation, staleness)
            }
            return .available(presentation)
        }
        if let metadata = map.unavailableSavedLocations.first(where: {
            $0.scope == .location(locationID)
        }) {
            return .unavailable(metadata)
        }
        return .notFound(locationID)
    }
}

struct LocationDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var location: GeoLocation

    @State private var newItemName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        List {
            Section("Items") {
                if location.shoppingItems.isEmpty {
                    Text("No items yet")
                        .foregroundStyle(.secondary)
                }

                ForEach(location.shoppingItems) { item in
                    HStack {
                        Button {
                            withAnimation {
                                item.isCompleted.toggle()
                            }
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.isCompleted ? .green : .gray)
                                .animation(.spring(), value: item.isCompleted)
                        }
                        .buttonStyle(.plain)

                        if let imageData = item.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Text(item.name)
                            .strikethrough(item.isCompleted)

                        Spacer()
                    }
                }
                .onDelete(perform: deleteItems)
            }

            Section("Add Item") {
                TextField("Item name", text: $newItemName)

                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images
                ) {
                    Label("Choose Photo", systemImage: "photo")
                }

                if let selectedImageData,
                   let uiImage = UIImage(data: selectedImageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                }

                Button("Add Item") {
                    addItem()
                }
                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(location.title)
        .onChange(of: selectedPhotoItem) {
            loadSelectedPhoto()
        }
    }

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return
        }

        let item = ShoppingItem(
            name: name,
            isCompleted: false,
            imageData: selectedImageData
        )

        location.shoppingItems.append(item)

        newItemName = ""
        selectedPhotoItem = nil
        selectedImageData = nil
    }

    private func loadSelectedPhoto() {
        Task {
            selectedImageData = try? await selectedPhotoItem?.loadTransferable(type: Data.self)
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = location.shoppingItems[index]
            location.shoppingItems.remove(at: index)
            modelContext.delete(item)
        }
    }
}

// T-18 target presentation remains inactive until the approved cutover.
