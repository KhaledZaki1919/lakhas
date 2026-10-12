import Foundation
import LakhasKit
import Testing

/// Proves on a real TLS connection that `PinningDelegate` is actually invoked and enforces pins:
/// www.google.com chains to Google Trust Services, so the GTS pins must pass and a wrong pin must
/// fail. Needs network (the CI runner has it).
@Suite(.serialized)
struct PinningLiveTests {
    private static let gtsPins: Set<String> = [
        "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=",   // GTS Root R1
        "Vfd95BwDeSQo+NUYxVEEIlvkOlWY2SalKK1lPhzOx78=",   // GTS Root R2
        "QXnt2YHvdHR3tJYmQIr0Paosp6t/nggsEGD4QJZ3Q0g=",   // GTS Root R3
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=",   // GTS Root R4
    ]

    private func fetch(pins: Set<String>) async -> Result<Int, Error> {
        let delegate = PinningDelegate(validator: PinValidator(host: "www.google.com", pins: pins))
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: "https://www.google.com/generate_204") else { return .failure(URLError(.badURL)) }
        do {
            let (_, response) = try await session.data(from: url)
            return .success((response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return .failure(error)
        }
    }

    @Test func acceptsAChainEndingInAPinnedRoot() async throws {
        let result = await fetch(pins: Self.gtsPins)
        #expect((try? result.get()) == 204)
    }

    @Test func rejectsWhenNoPinMatches() async {
        let result = await fetch(pins: ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="])
        guard case .failure(let error) = result else {
            Issue.record("request succeeded despite a wrong pin")
            return
        }
        #expect((error as? URLError)?.code == .cancelled)
    }

    @Test func appShipsCAPins() {
        let pins = Bundle.main.object(forInfoDictionaryKey: "LakhasPinnedSPKI") as? [String] ?? []
        #expect(pins.count >= 4)
        #expect(pins.allSatisfy { Data(base64Encoded: $0)?.count == 32 })
    }
}
