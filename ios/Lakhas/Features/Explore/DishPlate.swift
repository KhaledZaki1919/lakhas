import LakhasKit
import SwiftUI
import UIKit

/// No AI images (PROJECT_PROMPT.md §4.9): a dish shows the user's own photo, otherwise its
/// category symbol on a tinted plate.
extension DishCategory {
    var symbol: String {
        switch self {
        case .beans: "circle.hexagongrid.fill"
        case .eggs: "frying.pan.fill"
        case .dairy: "cube.fill"
        case .bread: "takeoutbag.and.cup.and.straw.fill"
        case .rice: "fork.knife"
        case .stew: "cooktop.fill"
        case .grill: "flame.fill"
        case .fish: "fish.fill"
        case .salad: "carrot.fill"
        case .soup: "mug.fill"
        case .pasta: "fork.knife.circle.fill"
        case .sweet: "birthday.cake.fill"
        case .fruit: "basket.fill"
        case .snack: "popcorn.fill"
        case .drink: "cup.and.saucer.fill"
        }
    }

    var tint: Color {
        switch self {
        case .beans, .fruit: Theme.Palette.plateOlive
        case .eggs, .bread, .soup: Theme.Palette.plateWheat
        case .dairy, .rice: Theme.Palette.plateTahini
        case .stew, .grill, .pasta: Theme.Palette.accent
        case .fish, .salad, .drink: Theme.Palette.primary
        case .sweet, .snack: Theme.Palette.plateEggplant
        }
    }
}

/// The user's photo of the dish, or the category plate. `size` is the plate's diameter.
struct DishImage: View {
    let category: DishCategory
    let photoFileName: String?
    var size: CGFloat = 44

    var body: some View {
        if let photoFileName, let image = UIImage(contentsOfFile: MealPhotoStore().url(for: photoFileName).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Palette.line, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            DishPlate(category: category, size: size)
        }
    }
}

/// A plate seen from above: rim, tinted well, category symbol.
struct DishPlate: View {
    let category: DishCategory
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.Palette.surface)
            Circle().stroke(Theme.Palette.halo, lineWidth: max(2, size * 0.06))
            Circle()
                .fill(category.tint.opacity(0.16))
                .padding(size * 0.14)
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(category.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The dish screen's header: the user's photo across the full width, or a large plate on a tinted field.
struct DishHero: View {
    let category: DishCategory
    let photoFileName: String?

    var body: some View {
        Group {
            if let photoFileName, let image = UIImage(contentsOfFile: MealPhotoStore().url(for: photoFileName).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    category.tint.opacity(0.10)
                    DishPlate(category: category, size: 128)
                        .shadow(color: Theme.Palette.ink.opacity(0.08), radius: 10, y: 4)
                }
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityHidden(true)
    }
}
