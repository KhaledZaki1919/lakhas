import Foundation
import LakhasKit
import Testing

/// Runs inside the app host on the Simulator.
struct AppConfigurationTests {
    @Test func infoPlistDeclaresDefaultAppGroup() {
        let group = Bundle.main.object(forInfoDictionaryKey: AppGroupResolver.infoPlistKey) as? String
        #expect(group == "group.com.khaled.lakhas")
    }

    @Test func infoPlistDeclaresHTTPSBaseURL() throws {
        let value = try #require(Bundle.main.object(forInfoDictionaryKey: "LakhasAPIBaseURL") as? String)
        #expect(URL(string: value)?.scheme == "https")
    }

    @Test func resolvedStoreIsWritable() {
        let location = AppGroupResolver.resolve()
        #expect(FileManager.default.isWritableFile(atPath: location.directory.path))
    }
}
