//
//  SpaceTargetTests.swift
//  SpacemanTests
//
//  Created by Conner Stobie on 2026-10-19.
//  Co-author: Claude Code
//

import XCTest
@testable import Spaceman

final class SpaceTargetTests: XCTestCase {

    private func space(_ spaceID: String, _ name: String, _ number: Int, current: Bool = false) -> Space {
        Space(
            displayID: "D1", spaceID: spaceID, spaceName: name,
            spaceNumber: number, spaceLabel: String(number),
            isCurrentSpace: current, isFullScreen: false)
    }

    private lazy var spaces: [Space] = [
        space("352", "Mail", 1),
        space("5", "Music Room", 2),
        space("7", "Code Review", 3, current: true),
        space("6", "Code", 4),
        space("3", "Photos", 5),
    ]

    func testNameMatchesExactly() {
        XCTAssertEqual(SpaceTarget.resolve(.name("Code"), in: spaces), .found(spaces[3]))
    }

    func testNameMatchIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(SpaceTarget.resolve(.name("  music room "), in: spaces), .found(spaces[1]))
    }

    func testNameDoesNotMatchPrefix() {
        // "Code" must not pick "Code Review", and "Code R" matches nothing.
        XCTAssertEqual(SpaceTarget.resolve(.name("Code R"), in: spaces), .notFound)
    }

    func testNumericNameFallsBackToNumber() {
        XCTAssertEqual(SpaceTarget.resolve(.name("5"), in: spaces), .found(spaces[4]))
    }

    func testNameThatIsANumberWinsOverPosition() {
        let numbered = [space("10", "2", 1), space("11", "Other", 2)]
        XCTAssertEqual(SpaceTarget.resolve(.name("2"), in: numbered), .found(numbered[0]))
    }

    func testNumber() {
        XCTAssertEqual(SpaceTarget.resolve(.number(1), in: spaces), .found(spaces[0]))
        XCTAssertEqual(SpaceTarget.resolve(.number(9), in: spaces), .notFound)
    }

    func testSpaceID() {
        XCTAssertEqual(SpaceTarget.resolve(.spaceID("6"), in: spaces), .found(spaces[3]))
        XCTAssertEqual(SpaceTarget.resolve(.spaceID("999"), in: spaces), .notFound)
    }

    func testDuplicateNamesAreAmbiguous() {
        let twins = [space("1", "Work", 1), space("2", "work", 2)]
        XCTAssertEqual(SpaceTarget.resolve(.name("Work"), in: twins), .ambiguous(count: 2))
    }

    func testEmptyNameIsNotFound() {
        XCTAssertEqual(SpaceTarget.resolve(.name("   "), in: spaces), .notFound)
    }

    func testCurrentSpaceStillResolves() {
        XCTAssertEqual(SpaceTarget.resolve(.name("Code Review"), in: spaces), .found(spaces[2]))
    }

    func testCommandParameterParsing() {
        XCTAssertEqual(SwitchToSpaceCommand.target(direct: "Code", spaceID: nil), .name("Code"))
        XCTAssertEqual(SwitchToSpaceCommand.target(direct: NSNumber(value: 3), spaceID: nil), .number(3))
        XCTAssertEqual(SwitchToSpaceCommand.target(direct: nil, spaceID: NSNumber(value: 6)), .spaceID("6"))
        XCTAssertEqual(SwitchToSpaceCommand.target(direct: "Code", spaceID: NSNumber(value: 6)), .spaceID("6"))
        XCTAssertNil(SwitchToSpaceCommand.target(direct: nil, spaceID: nil))
    }
}
