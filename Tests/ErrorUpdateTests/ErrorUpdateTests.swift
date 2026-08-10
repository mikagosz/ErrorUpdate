import Testing
@testable import ErrorUpdate
import Foundation

@Suite struct VersionComparisonTests {

    @Test func newerVersion_isGreater() {
        #expect(UpdateChecker.isVersion("1.1.0", greaterThan: "1.0.0"))
        #expect(UpdateChecker.isVersion("2.0.0", greaterThan: "1.9.9"))
        #expect(UpdateChecker.isVersion("1.0.1", greaterThan: "1.0"))
    }

    @Test func olderOrEqualVersion_isNotGreater() {
        #expect(!UpdateChecker.isVersion("1.0.0", greaterThan: "1.0.0"))
        #expect(!UpdateChecker.isVersion("1.0.0", greaterThan: "1.0.1"))
        #expect(!UpdateChecker.isVersion("1.0", greaterThan: "1.0.0"))
    }

    @Test func prereleaseVersions_compareCorrectly() {
        // Release is newer than its own pre-release
        #expect(UpdateChecker.isVersion("1.2.0", greaterThan: "1.2.0-beta"))
        #expect(!UpdateChecker.isVersion("1.2.0-beta", greaterThan: "1.2.0"))
        // Higher core version wins regardless of pre-release
        #expect(UpdateChecker.isVersion("1.3.0-beta", greaterThan: "1.2.0"))
    }

    @Test func contentHash_isStableAndUnique() {
        let a = ErrorReport(errorMessage: "Boom", stackTrace: ["f1", "f2"])
        let b = ErrorReport(errorMessage: "Boom", stackTrace: ["f1", "f2"])
        let c = ErrorReport(errorMessage: "Other", stackTrace: ["f1", "f2"])

        #expect(a.contentHash == b.contentHash)
        #expect(a.contentHash != c.contentHash)
        #expect(!a.contentHash.isEmpty)
    }
}
