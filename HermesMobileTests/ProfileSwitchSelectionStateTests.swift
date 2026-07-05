import XCTest
@testable import HermesMobile

/// Covers the default-profile picker's checkmark state machine, in particular
/// the failed-switch rollback (upstream issue #59): a profile the server
/// rejected must not keep showing as selected.
final class ProfileSwitchSelectionStateTests: XCTestCase {
    func testSuccessfulSaveSelectsTheNewProfile() {
        var state = ProfileSwitchSelectionState()
        state.setActive("default")

        state.beginSave(name: "staging")
        XCTAssertTrue(state.isSelected(profileNamed: "staging"))

        state.completeSave(activeName: "staging")
        XCTAssertTrue(state.isSelected(profileNamed: "staging"))
        XCTAssertNil(state.saveError)
    }

    func testFailedSaveRollsBackTheOptimisticSelection() {
        var state = ProfileSwitchSelectionState()
        state.setActive("default")

        state.beginSave(name: "staging")
        state.failSave(message: "profile not found")

        XCTAssertEqual(state.saveError, "profile not found")
        XCTAssertFalse(
            state.isSelected(profileNamed: "staging"),
            "A profile the server rejected must not keep its checkmark"
        )
        XCTAssertTrue(
            state.isSelected(profileNamed: "default"),
            "The real active profile stays selected after a failed switch"
        )
    }

    func testRetryAfterFailureClearsTheError() {
        var state = ProfileSwitchSelectionState()
        state.setActive("default")

        state.beginSave(name: "staging")
        state.failSave(message: "timeout")
        state.beginSave(name: "staging")

        XCTAssertNil(state.saveError)
        XCTAssertTrue(state.isSelected(profileNamed: "staging"))
    }

    func testSavingIndicatorTracksOnlyTheAttemptedProfile() {
        var state = ProfileSwitchSelectionState()
        state.beginSave(name: "staging")

        XCTAssertTrue(state.isSaving(profileNamed: "staging"))
        XCTAssertFalse(state.isSaving(profileNamed: "default"))
        XCTAssertFalse(state.isSaving(profileNamed: nil))
    }
}
