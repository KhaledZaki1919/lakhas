import Foundation
import Testing
@testable import LakhasKit

/// Builds CMS-shaped envelopes around a plist the way different signers encode them.
private enum BER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func indefinite(_ tag: UInt8, _ children: [[UInt8]]) -> [UInt8] {
        [tag, 0x80] + children.flatMap { $0 } + [0x00, 0x00]
    }

    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static let oidSignedData: [UInt8] = tlv(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02])
    static let oidData: [UInt8] = tlv(0x06, [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01])
    static let version: [UInt8] = tlv(0x02, [0x01])
    static let emptySet: [UInt8] = tlv(0x31, [])

    /// Definite-length DER, payload in one OCTET STRING (Apple's layout).
    static func der(payload: [UInt8]) -> Data {
        let encap = tlv(0x30, oidData + tlv(0xA0, tlv(0x04, payload)))
        let signedData = tlv(0x30, version + emptySet + encap + emptySet)
        return Data(tlv(0x30, oidSignedData + tlv(0xA0, signedData)))
    }

    /// Indefinite-length BER with the payload split across a constructed OCTET STRING.
    static func chunked(payload: [UInt8], chunkSize: Int) -> Data {
        let chunks = stride(from: 0, to: payload.count, by: chunkSize).map {
            tlv(0x04, Array(payload[$0..<min($0 + chunkSize, payload.count)]))
        }
        let encap = indefinite(0x30, [oidData, indefinite(0xA0, [indefinite(0x24, chunks)])])
        let signedData = indefinite(0x30, [version, emptySet, encap, emptySet])
        return Data(indefinite(0x30, [oidSignedData, indefinite(0xA0, [signedData])]))
    }
}

struct CMSContentTests {
    private static let plist = Array("""
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
    <key>Name</key><string>Chunked Profile</string>
    <key>TeamIdentifier</key><array><string>ZZZZZ99999</string></array>
    <key>Entitlements</key><dict>
    <key>application-identifier</key><string>ZZZZZ99999.com.khaled.lakhas</string>
    <key>keychain-access-groups</key><array><string>ZZZZZ99999.*</string></array>
    </dict></dict></plist>
    """.utf8)

    @Test func extractsPayloadFromDER() {
        #expect(CMSContent.extract(BER.der(payload: Self.plist)) == Data(Self.plist))
    }

    @Test func extractsPayloadFromChunkedBER() {
        #expect(CMSContent.extract(BER.chunked(payload: Self.plist, chunkSize: 64)) == Data(Self.plist))
    }

    @Test func profileParsesFromChunkedBERWhereTextSearchFails() throws {
        let data = BER.chunked(payload: Self.plist, chunkSize: 64)
        // The plist text is interrupted by chunk headers, so the closing marker isn't contiguous.
        let profile = try #require(ProvisioningProfile.parse(data))
        #expect(profile.name == "Chunked Profile")
        #expect(profile.teamIdentifiers == ["ZZZZZ99999"])
        #expect(profile.appGroups.isEmpty)
        #expect(profile.entitlementKeys == ["application-identifier", "keychain-access-groups"])
    }

    @Test func rejectsGarbage() {
        #expect(CMSContent.extract(Data([0x30, 0x05, 0x01])) == nil)
        #expect(CMSContent.extract(Data()) == nil)
    }
}
