//
//  SpaceTarget.swift
//  Spaceman
//
//  Created by Conner Stobie on 2026-10-19.
//  Co-author: Claude Code
//

import Foundation

/// The space an AppleScript "switch to space" command asked for.
enum SpaceTarget: Equatable {
    /// A user-assigned space name, as shown in the menu bar.
    case name(String)
    /// The sequential space number, as returned by "current space number".
    case number(Int)
    /// The macOS ManagedSpaceID. Exact, but only valid until the next reboot or wake.
    case spaceID(String)

    enum Resolution: Equatable {
        case found(Space)
        case notFound
        case ambiguous(count: Int)
    }

    /// Find the space a target refers to.
    /// Names match case-insensitively after trimming. A name that matches no
    /// space but parses as an integer is treated as a space number, so
    /// `switch to space "3"` behaves like `switch to space 3`.
    static func resolve(_ target: SpaceTarget, in spaces: [Space]) -> Resolution {
        switch target {
        case .spaceID(let spaceID):
            guard let match = spaces.first(where: { $0.spaceID == spaceID }) else { return .notFound }
            return .found(match)
        case .number(let number):
            guard let match = spaces.first(where: { $0.spaceNumber == number }) else { return .notFound }
            return .found(match)
        case .name(let raw):
            let wanted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else { return .notFound }
            let matches = spaces.filter {
                $0.spaceName.caseInsensitiveCompare(wanted) == .orderedSame
            }
            if matches.count > 1 { return .ambiguous(count: matches.count) }
            if let match = matches.first { return .found(match) }
            if let number = Int(wanted) { return resolve(.number(number), in: spaces) }
            return .notFound
        }
    }
}
