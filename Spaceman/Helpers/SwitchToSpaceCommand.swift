//
//  SwitchToSpaceCommand.swift
//  Spaceman
//
//  Created by Conner Stobie on 2026-10-19.
//  Co-author: Claude Code
//

import Foundation
import Cocoa

/// AppleScript: `switch to space "Mail"`, `switch to space 3`, `switch to space with space id 6`.
/// Starts the switch through the same path as choosing the space in the menu
/// and returns true; the switch itself finishes asynchronously, so callers
/// that need to know it landed should poll "current space name".
class SwitchToSpaceCommand: NSScriptCommand {
    private static let missingParameterError = -1715  // errAEParamMissed
    private static let noSuchObjectError = -1728      // errAENoSuchObject

    override func performDefaultImplementation() -> Any? {
        guard let target = Self.target(
            direct: directParameter, spaceID: evaluatedArguments?["spaceID"]
        ) else {
            scriptErrorNumber = Self.missingParameterError
            scriptErrorString = "Give a space name or number, or a space id."
            return nil
        }
        guard let appDelegate = AppDelegate.shared else {
            scriptErrorNumber = Self.noSuchObjectError
            scriptErrorString = "Spaceman has not finished launching."
            return nil
        }
        switch appDelegate.switchToSpace(matching: target) {
        case .found:
            return true
        case .notFound:
            scriptErrorNumber = Self.noSuchObjectError
            scriptErrorString = "No space matches \(Self.describe(target))."
            return nil
        case .ambiguous(let count):
            scriptErrorNumber = Self.noSuchObjectError
            scriptErrorString = "\(count) spaces are named \(Self.describe(target))."
            return nil
        }
    }

    static func target(direct: Any?, spaceID: Any?) -> SpaceTarget? {
        if let number = spaceID as? NSNumber { return .spaceID(number.stringValue) }
        if let text = spaceID as? String, !text.isEmpty { return .spaceID(text) }
        if let number = direct as? NSNumber { return .number(number.intValue) }
        if let text = direct as? String { return .name(text) }
        return nil
    }

    private static func describe(_ target: SpaceTarget) -> String {
        switch target {
        case .name(let name): return "\"\(name)\""
        case .number(let number): return "number \(number)"
        case .spaceID(let spaceID): return "id \(spaceID)"
        }
    }
}
