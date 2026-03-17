import AppKit
import KnokCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var socketServer: SocketServer?
    private let alertEngine = AlertEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Ensure socket directory exists
        let socketDir = KnokConstants.socketDir
        try? FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)

        // Start socket server
        socketServer = SocketServer(alertEngine: alertEngine)
        socketServer?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        // Clean up socket file
        try? FileManager.default.removeItem(atPath: KnokConstants.socketPath)
    }
}
