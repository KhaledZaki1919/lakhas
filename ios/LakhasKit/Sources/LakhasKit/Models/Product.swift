import Foundation
import SwiftData

/// Where a product's values came from.
public enum ProductSource: String, Codable, Sendable {
    /// Open Food Facts (ODbL), saved locally once the user logs it.
    case openFoodFacts
    /// Read from two label photos by the user's AI provider, then confirmed by the user.
    case label
    /// Typed or edited by the user.
    case manual
}

/// A packaged product the user has logged or added (ADR-020: stays on this device, never shared).
@Model
public final class Product {
    /// Canonical barcode (`Barcode.normalize`).
    @Attribute(.unique) public var barcode: String
    public var nameAr: String
    public var nameEn: String
    public var brand: String?
    public var servingGrams: Double?
    public var kcalPer100: Double
    public var proteinPer100: Double
    public var carbsPer100: Double
    public var fatPer100: Double
    public var sourceRaw: String
    /// Front photo in `MealPhotoStore` (device only), if the user took one.
    public var photoFileName: String?
    public var createdAt: Date
    public var lastUsedAt: Date

    public init(info: ProductInfo, now: Date = .now) {
        barcode = info.barcode
        nameAr = info.nameAr
        nameEn = info.nameEn
        brand = info.brand
        servingGrams = info.servingGrams
        kcalPer100 = info.per100?.kcal ?? 0
        proteinPer100 = info.per100?.protein ?? 0
        carbsPer100 = info.per100?.carbs ?? 0
        fatPer100 = info.per100?.fat ?? 0
        sourceRaw = info.source.rawValue
        createdAt = now
        lastUsedAt = now
    }

    public var source: ProductSource { ProductSource(rawValue: sourceRaw) ?? .manual }

    public var per100: Macros {
        Macros(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }

    public func update(from info: ProductInfo) {
        nameAr = info.nameAr
        nameEn = info.nameEn
        brand = info.brand
        servingGrams = info.servingGrams
        kcalPer100 = info.per100?.kcal ?? 0
        proteinPer100 = info.per100?.protein ?? 0
        carbsPer100 = info.per100?.carbs ?? 0
        fatPer100 = info.per100?.fat ?? 0
        sourceRaw = info.source.rawValue
    }

    public var info: ProductInfo {
        ProductInfo(barcode: barcode, nameAr: nameAr, nameEn: nameEn, brand: brand, servingGrams: servingGrams,
                    per100: per100, source: source, isSaved: true)
    }
}

/// A product as shown on the barcode screens, from the local library, Open Food Facts or a label.
public struct ProductInfo: Equatable, Sendable {
    public var barcode: String
    public var nameAr: String
    public var nameEn: String
    public var brand: String?
    public var servingGrams: Double?
    /// nil when the source has no usable nutrition values.
    public var per100: Macros?
    public var source: ProductSource
    /// Already in the local product library.
    public var isSaved: Bool

    public init(barcode: String, nameAr: String, nameEn: String, brand: String? = nil, servingGrams: Double? = nil,
                per100: Macros?, source: ProductSource, isSaved: Bool = false) {
        self.barcode = barcode
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.brand = brand
        self.servingGrams = servingGrams
        self.per100 = per100
        self.source = source
        self.isSaved = isSaved
    }

    public func name(language: String) -> String {
        language == "ar" ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    /// One review line for `grams` of this product.
    public func draftItem(grams: Double) -> DraftItem {
        DraftItem(nameAr: nameAr.isEmpty ? nameEn : nameAr, nameEn: nameEn.isEmpty ? nameAr : nameEn,
                  grams: grams, per100: per100 ?? .zero, valueSource: .product, barcode: barcode)
    }

    /// Same plausibility rules as AI answers: kcal 0–900, each macro 0–100, macros ≤ 100 g per 100 g.
    public static func isPlausible(_ per100: Macros) -> Bool {
        (0...900).contains(per100.kcal)
            && [per100.protein, per100.carbs, per100.fat].allSatisfy { (0...100).contains($0) }
            && per100.protein + per100.carbs + per100.fat <= 101
    }
}

/// EAN/UPC barcodes as one canonical string, so a product scanned as UPC-A and typed as
/// EAN-13 is the same local product.
public enum Barcode {
    /// Western digits (Eastern Arabic digits are converted; spaces and dashes are ignored).
    /// UPC-A (12) becomes EAN-13 with a leading 0, GTIN-14 with a leading 0 becomes EAN-13.
    /// Returns nil unless the result is EAN-8/UPC-E (8) or EAN-13 with a valid check digit.
    public static func normalize(_ raw: String) -> String? {
        var digits = ""
        for character in raw where !character.isWhitespace && character != "-" {
            guard character.isNumber, let value = character.wholeNumberValue else { return nil }
            digits += String(value)
        }
        if digits.count == 12 { digits = "0" + digits }
        if digits.count == 14, digits.hasPrefix("0") { digits.removeFirst() }
        switch digits.count {
        case 8: return digits
        case 13: return hasValidCheckDigit(digits) ? digits : nil
        default: return nil
        }
    }

    /// GTIN mod-10: weights 3 and 1 alternate from the digit before the check digit.
    static func hasValidCheckDigit(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, let check = values.last else { return false }
        let sum = values.dropLast().reversed().enumerated().reduce(0) { total, pair in
            total + pair.element * (pair.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }
}
