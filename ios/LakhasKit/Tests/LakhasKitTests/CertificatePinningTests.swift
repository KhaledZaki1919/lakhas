import Foundation
import Security
import Testing
@testable import LakhasKit

/// Expected values computed with OpenSSL from the CAs' published root certificates:
/// `openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64`
struct SPKIHashTests {
    private func certificate(_ name: String) throws -> SecCertificate {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "der", subdirectory: "Fixtures"))
        return try #require(SecCertificateCreateWithData(nil, try Data(contentsOf: url) as CFData))
    }

    @Test func rsa4096Root() throws {
        #expect(SPKIHash.sha256Base64(of: try certificate("isrg-root-x1")) == "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=")
    }

    @Test func ecP384Roots() throws {
        #expect(SPKIHash.sha256Base64(of: try certificate("gts-root-r4")) == "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=")
        #expect(SPKIHash.sha256Base64(of: try certificate("isrg-root-x2")) == "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=")
    }

    @Test func derLengthEncoding() {
        #expect(DER.length(5) == [0x05])
        #expect(DER.length(0x80) == [0x81, 0x80])
        #expect(DER.length(0x020F) == [0x82, 0x02, 0x0F])
    }
}
