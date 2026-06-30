import SwiftUI
import SwiftData
import PhotosUI

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

