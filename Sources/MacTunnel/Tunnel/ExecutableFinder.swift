import Foundation

/// Searches common PATH locations for an executable.
func findExecutable(_ name: String) -> String? {
    let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .components(separatedBy: ":")
        + ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]

    for dir in searchPaths {
        let full = (dir as NSString).appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: full) {
            return full
        }
    }
    return nil
}
