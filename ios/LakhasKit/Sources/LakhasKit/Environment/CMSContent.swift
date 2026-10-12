import Foundation

/// Minimal BER/DER reader that extracts the signed payload (`encapContentInfo.eContent`)
/// from a CMS `SignedData` envelope such as `embedded.mobileprovision`.
///
/// Apple's tools store the plist as one contiguous OCTET STRING, but other signers may use
/// BER with indefinite lengths and a *constructed* OCTET STRING split into chunks, which
/// breaks a plain text search for the plist. iOS has no public CMS decoder, hence this.
enum CMSContent {
    private struct TLV {
        let tag: UInt8
        let contentStart: Int
        let contentEnd: Int
        let next: Int
    }

    private static let sequence: UInt8 = 0x30
    private static let contextZero: UInt8 = 0xA0          // [0] EXPLICIT, constructed
    private static let octetString: UInt8 = 0x04
    private static let constructedOctetString: UInt8 = 0x24

    static func extract(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        // ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT SignedData }
        guard let contentInfo = parse(bytes, at: 0), contentInfo.tag == sequence else { return nil }
        let infoFields = children(bytes, of: contentInfo)
        guard infoFields.count >= 2, infoFields[1].tag == contextZero,
              let signedData = children(bytes, of: infoFields[1]).first, signedData.tag == sequence
        else { return nil }

        // SignedData ::= SEQUENCE { version, digestAlgorithms, encapContentInfo, ... }
        let signedFields = children(bytes, of: signedData)
        guard signedFields.count >= 3, signedFields[2].tag == sequence else { return nil }

        // EncapsulatedContentInfo ::= SEQUENCE { eContentType OID, eContent [0] EXPLICIT OCTET STRING }
        let encapFields = children(bytes, of: signedFields[2])
        guard encapFields.count >= 2, encapFields[1].tag == contextZero,
              let content = children(bytes, of: encapFields[1]).first
        else { return nil }

        let payload = octets(bytes, of: content)
        return payload.isEmpty ? nil : Data(payload)
    }

    private static func parse(_ bytes: [UInt8], at index: Int) -> TLV? {
        guard index + 1 < bytes.count else { return nil }
        let tag = bytes[index]
        var position = index + 1
        let first = bytes[position]
        position += 1

        if first == 0x80 {
            // Indefinite length: children until the end-of-contents marker 00 00.
            var cursor = position
            while cursor + 1 < bytes.count, !(bytes[cursor] == 0 && bytes[cursor + 1] == 0) {
                guard let child = parse(bytes, at: cursor) else { return nil }
                cursor = child.next
            }
            guard cursor + 1 < bytes.count else { return nil }
            return TLV(tag: tag, contentStart: position, contentEnd: cursor, next: cursor + 2)
        }

        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard (1...4).contains(count), position + count <= bytes.count else { return nil }
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[position])
                position += 1
            }
        }
        guard position + length <= bytes.count else { return nil }
        return TLV(tag: tag, contentStart: position, contentEnd: position + length, next: position + length)
    }

    private static func children(_ bytes: [UInt8], of parent: TLV) -> [TLV] {
        var result: [TLV] = []
        var cursor = parent.contentStart
        while cursor < parent.contentEnd, let child = parse(bytes, at: cursor) {
            result.append(child)
            cursor = child.next
        }
        return result
    }

    private static func octets(_ bytes: [UInt8], of node: TLV) -> [UInt8] {
        switch node.tag {
        case octetString:
            return Array(bytes[node.contentStart..<node.contentEnd])
        case constructedOctetString:
            return children(bytes, of: node).flatMap { octets(bytes, of: $0) }
        default:
            return []
        }
    }
}
