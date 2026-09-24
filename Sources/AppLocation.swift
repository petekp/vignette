import AppKit
import os

/// Where the app runs from. Opened from its disk image, it runs from a read-only volume, or from a
/// random read-only path when macOS translocates a downloaded app. From there a login item points at
/// a path that goes away with the image, and the image cannot be ejected while the app runs. A
/// launch from there offers to move the app to Applications, reopens it from there, and the new
/// copy ejects the image.
enum AppLocation {
    /// The argument the moved copy is opened with, followed by the disk image's volume path.
    static let ejectArgument = "--eject-disk-image"

    /// Runs first in `main`, before settings exist: the moved copy is the one that sets up the
    /// settings file, Apple's screenshot defaults and the watcher. Returns only when this copy
    /// should go on launching.
    @MainActor
    static func offerMove() {
        let bundle = Bundle.main.bundleURL
        guard isOnDiskImage(bundle) else { return }
        let destination = destination(for: bundle)
        Log.write("[install] running from \(bundle.path); offering \(destination.path)")

        let alert = NSAlert()
        alert.messageText = "Move \(Identity.name) to Applications?"
        alert.informativeText = "\(Identity.name) is running from the disk image. Moving it to Applications lets it open at login and ejects the disk image."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            Log.write("[install] quit without moving")
            exit(0)
        }

        do {
            try move(bundle, to: destination)
        } catch {
            Log.write("[install] error move failed: \(error.localizedDescription)")
            let failed = NSAlert()
            failed.messageText = "\(Identity.name) couldn't be moved to Applications."
            failed.informativeText = "Drag \(Identity.name) from the disk image to your Applications folder, then open it from there."
            failed.runModal()
            exit(1)
        }
        Log.write("[install] moved to \(destination.path)")
        reopen(destination, ejecting: diskImageVolume(of: bundle))
        exit(0)
    }

    /// In the moved copy: ejects the disk image it was moved from once the copy that moved it has
    /// quit, which is when the volume stops being busy.
    static func ejectDiskImageIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: ejectArgument), i + 1 < args.count else { return }
        let volume = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        guard isOnReadOnlyVolume(volume) else { return }
        eject(volume, attemptsLeft: 10)
    }

    /// A disk image is a read-only volume, and so is the path macOS translocates an app to; a build
    /// folder and Applications are neither.
    private static func isOnDiskImage(_ url: URL) -> Bool {
        isTranslocated(url) || isOnReadOnlyVolume(url)
    }

    private static func isTranslocated(_ url: URL) -> Bool { url.path.contains("/AppTranslocation/") }

    private static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
    }

    /// /Applications when this user may write there, ~/Applications otherwise: a standard user
    /// cannot write to /Applications, and both are folders LaunchServices and login items know.
    private static func destination(for bundle: URL) -> URL {
        let shared = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = FileManager.default.isWritableFile(atPath: shared.path)
            ? shared
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        return folder.appendingPathComponent(bundle.lastPathComponent)
    }

    /// Copies beside the destination first, so a copy that fails part way leaves nothing in
    /// Applications. An older copy already there goes to the Trash rather than being deleted.
    private static func move(_ bundle: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        defer { try? fm.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(destination.lastPathComponent)
        try fm.copyItem(at: bundle, to: staged)
        clearQuarantine(staged)
        if fm.fileExists(atPath: destination.path) { try fm.trashItem(at: destination, resultingItemURL: nil) }
        try fm.moveItem(at: staged, to: destination)
    }

    /// The user already confirmed Gatekeeper's first-open dialog for this app. The copy carries
    /// the image's quarantine flag, and left on it would ask them the same question again.
    private static func clearQuarantine(_ url: URL) {
        let inside = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        for item in [url] + inside { removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW) }
    }

    /// The volume to eject: the one the bundle is on, or, for a translocated bundle, the mounted
    /// read-only volume holding a copy of this same build.
    private static func diskImageVolume(of bundle: URL) -> URL? {
        let volume = (try? bundle.resourceValues(forKeys: [.volumeURLKey]))?.volume
        if !isTranslocated(bundle) { return volume }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            guard isOnReadOnlyVolume(volume),
                  let copy = Bundle(url: volume.appendingPathComponent(bundle.lastPathComponent)) else { return false }
            return copy.bundleIdentifier == Identity.bundleID
                && copy.infoDictionary?["CFBundleVersion"] as? String == Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        }
    }

    /// Opens the moved copy as a new instance: without that, LaunchServices sees this bundle id
    /// running and brings this copy forward instead. The launch has not run the app loop yet, so
    /// the wait turns the run loop by hand.
    @MainActor
    private static func reopen(_ app: URL, ejecting volume: URL?) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        if let volume { configuration.arguments = [ejectArgument, volume.path] }
        // A launch on another settings file must not reopen on the user's own.
        if let settings = ProcessInfo.processInfo.environment["VIGNETTE_SETTINGS"] {
            configuration.environment = ["VIGNETTE_SETTINGS": settings]
        }
        let finished = OSAllocatedUnfairLock(initialState: false)
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { Log.write("[install] error reopen failed: \(error.localizedDescription)") }
            finished.withLock { $0 = true }
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished.withLock({ $0 }), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// `hdiutil detach`, not `NSWorkspace.unmountAndEjectDevice`: measured, that unmounts an APFS
    /// disk image's volume and leaves the image attached, so opening the same file again mounted
    /// nothing. The copy that moved the app runs from the volume until it has quit, and the volume
    /// stays busy until then, hence the retries.
    private static func eject(_ volume: URL, attemptsLeft: Int) {
        DispatchQueue.global(qos: .utility).async {
            let hdiutil = Process()
            hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutil.arguments = ["detach", volume.path, "-quiet"]
            do {
                try hdiutil.run()
                hdiutil.waitUntilExit()
            } catch {
                Log.write("[install] error eject \(volume.path): \(error.localizedDescription)")
                return
            }
            if hdiutil.terminationStatus == 0 {
                Log.write("[install] ejected \(volume.path)")
            } else if attemptsLeft > 1 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { eject(volume, attemptsLeft: attemptsLeft - 1) }
            } else {
                Log.write("[install] error eject \(volume.path): hdiutil exit \(hdiutil.terminationStatus)")
            }
        }
    }
}
