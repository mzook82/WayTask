import SwiftUI

struct MapFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedCategory: MapCategory
    @Binding var shoppingListOnly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WayTaskSearchField(placeholder: "Search places or items", text: $searchText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MapCategory.allCases) { category in
                        WayTaskFilterChip(
                            title: category.rawValue,
                            isSelected: selectedCategory == category
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                selectedCategory = category
                            }
                        }
                    }

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            shoppingListOnly.toggle()
                        }
                    } label: {
                        Label("Shopping List", systemImage: shoppingListOnly ? "checkmark.circle.fill" : "list.bullet.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(shoppingListOnly ? .white : WayTaskDesign.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(shoppingListOnly ? WayTaskDesign.accentRed : WayTaskDesign.surface)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(shoppingListOnly ? Color.clear : WayTaskDesign.surfaceBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter by shopping list items")
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
