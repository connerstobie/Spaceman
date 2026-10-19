// spacectl: read-only facts about macOS Spaces and app windows, printed as JSON.
//
//   spacectl spaces                    every display's Spaces in Mission Control order, and the active one
//   spacectl active                    the active Space's ManagedSpaceID on the main display
//   spacectl windows <bundle id>...    normal windows of those apps: id, title, Space ids, bounds
//   spacectl request-capture           ask macOS to list the calling app under Screen Recording
//
// Uses the same private, read-only CGS calls Spaceman uses (no SIP changes, no writes).
// Window titles need Screen Recording for the responsible process; without it "title" is null.
// Built and run by devspaces; compiled with: swiftc -O spacectl.swift -o spacectl

import AppKit
import CoreGraphics

typealias CGSConnectionID = Int32
@_silgen_name("_CGSDefaultConnection") func cgsDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSGetActiveSpace") func cgsGetActiveSpace(_ cid: CGSConnectionID) -> Int
@_silgen_name("CGSCopyManagedDisplaySpaces")
func cgsCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?
@_silgen_name("CGSCopySpacesForWindows")
func cgsCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?

let allSpacesMask: Int32 = 0x7

func emit(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
        FileHandle.standardError.write("spacectl: could not encode output\n".data(using: .utf8)!)
        exit(2)
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func spaces(_ cid: CGSConnectionID) -> [[String: Any]] {
    guard let raw = cgsCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
    return raw.map { display in
        let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        let list = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> [String: Any]? in
            guard let spaceID = space["ManagedSpaceID"] as? Int else { return nil }
            return [
                "id": spaceID,
                "uuid": space["uuid"] as? String ?? "",
                "fullscreen": space["TileLayoutManager"] is [String: Any],
            ]
        }
        return [
            "display": display["Display Identifier"] as? String ?? "",
            "current": current ?? NSNull(),
            "spaces": list,
        ]
    }
}

func windows(_ cid: CGSConnectionID, bundleIDs: Set<String>) -> [[String: Any]] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    var bundleByPID: [pid_t: String] = [:]
    var result: [[String: Any]] = []
    for window in info {
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let windowID = window[kCGWindowNumber as String] as? Int,
              (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
        if bundleByPID[pid] == nil {
            bundleByPID[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        }
        guard let bundle = bundleByPID[pid], bundleIDs.contains(bundle) else { continue }
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        // Skip tooltips, popovers and other helper surfaces.
        guard width >= 100, height >= 100 else { continue }
        let spaceIDs = cgsCopySpacesForWindows(cid, allSpacesMask, [windowID] as CFArray)?
            .takeRetainedValue() as? [Int] ?? []
        result.append([
            "id": windowID,
            "pid": Int(pid),
            "bundle": bundle,
            "title": (window[kCGWindowName as String] as? String) ?? NSNull(),
            "spaces": spaceIDs,
            "onscreen": (window[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            "x": bounds["X"] as? Double ?? 0,
            "y": bounds["Y"] as? Double ?? 0,
            "w": width,
            "h": height,
        ])
    }
    return result
}

let args = Array(CommandLine.arguments.dropFirst())
let cid = cgsDefaultConnection()
switch args.first {
case "spaces":
    emit(["active": cgsGetActiveSpace(cid), "displays": spaces(cid)])
case "active":
    print(cgsGetActiveSpace(cid))
case "request-capture":
    // Adds the calling app to the Screen Recording list so the user can switch it on.
    print(CGRequestScreenCaptureAccess())
case "windows" where args.count > 1:
    let listed = windows(cid, bundleIDs: Set(args.dropFirst()))
    emit(["titlesVisible": CGPreflightScreenCaptureAccess(), "windows": listed])
default:
    let usage = "usage: spacectl spaces | active | windows <bundle id>... | request-capture\n"
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(64)
}
