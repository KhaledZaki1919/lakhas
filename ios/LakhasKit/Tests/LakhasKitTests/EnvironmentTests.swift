import Foundation
import Testing
@testable import LakhasKit

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("LakhasKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct ProvisioningProfileTests {
    private static let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Name</key><string>Lakhas Free</string>
        <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
        <key>ExpirationDate</key><date>2026-10-18T12:00:00Z</date>
        <key>Entitlements</key>
        <dict>
            <key>application-identifier</key><string>ABCDE12345.com.khaled.lakhas</string>
            <key>com.apple.security.application-groups</key>
            <array><string>group.com.khaled.lakhas.ABCDE12345</string></array>
        </dict>
    </dict>
    </plist>
    """

    @Test func parsesPlistInsideBinaryEnvelope() throws {
        var data = Data([0x30, 0x82, 0x0F, 0x00, 0xFF])   // CMS-like noise before
        data.append(Data(Self.plist.utf8))
        data.append(Data([0x00, 0xA0, 0x82]))              // signature noise after

        let profile = try #require(ProvisioningProfile.parse(data))
        #expect(profile.name == "Lakhas Free")
        #expect(profile.teamIdentifiers == ["ABCDE12345"])
        #expect(profile.appGroups == ["group.com.khaled.lakhas.ABCDE12345"])
        #expect(profile.applicationIdentifier == "ABCDE12345.com.khaled.lakhas")
        #expect(profile.expirationDate != nil)
    }

    @Test func returnsNilWithoutPlist() {
        #expect(ProvisioningProfile.parse(Data("not a profile".utf8)) == nil)
    }
}

struct AppGroupResolverTests {
    @Test func candidatesPreferProfileGroupsAndDropDuplicates() {
        let ids = AppGroupResolver.candidateIDs(
            profileGroups: ["group.rewritten", "group.com.khaled.lakhas"],
            compiled: "group.com.khaled.lakhas"
        )
        #expect(ids == ["group.rewritten", "group.com.khaled.lakhas"])
    }

    @Test func usesFirstWritableContainer() throws {
        let shared = try makeTempDirectory()
        let fallback = try makeTempDirectory()
        let location = AppGroupResolver.resolve(
            candidates: ["group.missing", "group.ok"],
            containerURL: { $0 == "group.ok" ? shared : nil },
            fallback: fallback
        )
        #expect(location == StoreLocation(directory: shared, appGroupID: "group.ok"))
        #expect(location.isShared)
    }

    @Test func fallsBackWhenNoGroupIsUsable() throws {
        let fallback = try makeTempDirectory()
        let location = AppGroupResolver.resolve(
            candidates: ["group.a"], containerURL: { _ in nil }, fallback: fallback
        )
        #expect(location.directory == fallback)
        #expect(location.appGroupID == nil)
        #expect(!location.isShared)
    }
}

struct HeartbeatStoreTests {
    @Test func writesAndReadsEachRoleSeparately() throws {
        let store = HeartbeatStore(directory: try makeTempDirectory())
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        try store.write(Heartbeat(role: .widget, date: date, bundleID: "w", appGroupID: "g"))

        #expect(store.read(.widget) == Heartbeat(role: .widget, date: date, bundleID: "w", appGroupID: "g"))
        #expect(store.read(.app) == nil)
    }
}

struct PendingImportQueueTests {
    @Test func enqueuesListsOldestFirstAndRemoves() throws {
        let queue = PendingImportQueue(directory: try makeTempDirectory())
        let first = try queue.enqueue(
            url: try #require(URL(string: "https://www.tiktok.com/@cook/video/1")),
            now: Date(timeIntervalSince1970: 100)
        )
        try queue.enqueue(
            url: try #require(URL(string: "https://youtu.be/abc")),
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(queue.list().map(\.url.host) == ["www.tiktok.com", "youtu.be"])
        queue.remove(first)
        #expect(queue.list().count == 1)
    }
}
