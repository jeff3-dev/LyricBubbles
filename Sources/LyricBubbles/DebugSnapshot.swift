import AppKit

/// Debug aid: `defaults write local.lyricbubbles debugSnapshotPath /some/file.png`
/// makes the app save a PNG of its own window there (no Screen Recording permission needed),
/// then clears the key. `debugWindowInfoPath` does the same with a text dump of every window's
/// level, collection behavior and size limits.
enum DebugSnapshot {
    private static let key = "debugSnapshotPath"
    private static var timer: Timer?
    private static var infoTimer: Timer?
    private static let infoKey = "debugWindowInfoPath"

    static func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let defaults = UserDefaults.standard
            defaults.synchronize()
            guard let path = defaults.string(forKey: key), !path.isEmpty else { return }
            defaults.removeObject(forKey: key)
            save(to: URL(fileURLWithPath: path))
        }
        infoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let defaults = UserDefaults.standard
            guard let path = defaults.string(forKey: infoKey), !path.isEmpty else { return }
            defaults.removeObject(forKey: infoKey)
            let lines = NSApp.windows.map { w in
                "\(w.title) | \(type(of: w)) level=\(w.level.rawValue) behavior=\(w.collectionBehavior.rawValue) "
                    + "mask=\(w.styleMask.rawValue) resizable=\(w.styleMask.contains(.resizable)) "
                    + "min=\(w.minSize) max=\(w.maxSize) contentMax=\(w.contentMaxSize) "
                    + "visible=\(w.isVisible) fullscreen=\(w.styleMask.contains(.fullScreen)) "
                    + "fullScreenMax=\(w.contentMaxSize)"
            }
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func save(to url: URL) {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
