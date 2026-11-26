import Foundation

enum Shell {
    static let sudoersPath = "/private/etc/sudoers.d/supurgec"

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Kabuk için tek tırnakla güvenli alıntılama.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Yönetici parolası isteyerek komut çalıştırır.
    @MainActor
    static func runAsAdmin(_ command: String) -> (ok: Bool, output: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let (desc, err) = appleScript("do shell script \"\(escaped)\" with administrator privileges")
        if let err { return (false, err) }
        return (true, desc?.stringValue ?? "")
    }

    /// Tek seferlik parola kurulumuyla RAM boşaltır:
    /// İlk çalıştırmada yönetici onayı alıp yalnızca purge & DNS temizleme komutlarını
    /// yetkilendirir; sonraki tüm çalıştırmalarda şifre sormadan anında çalışır.
    static func freeRAMPasswordlessOrSetup() async -> Bool {
        let fast = await Task.detached(priority: .userInitiated) {
            Self.run("/usr/bin/sudo", ["-n", "/usr/sbin/purge"])
        }.value
        if fast.status == 0 { return true }
        return await installHelperAndRun(afterInstallCommand: "/usr/sbin/purge")
    }

    /// Tek seferlik parola kurulumuyla DNS önbelleğini temizler.
    static func flushDNSPasswordlessOrSetup() async -> Bool {
        let fast = await Task.detached(priority: .userInitiated) { () -> Int32 in
            let r1 = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/dscacheutil", "-flushcache"])
            let r2 = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/killall", "-HUP", "mDNSResponder"])
            return (r1.status == 0 && r2.status == 0) ? 0 : 1
        }.value
        if fast == 0 { return true }
        return await installHelperAndRun(afterInstallCommand: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")
    }

    @MainActor
    private static func installHelperAndRun(afterInstallCommand: String) -> Bool {
        let user = NSUserName()
        let validUser = user.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil
        guard validUser else {
            return runAsAdmin(afterInstallCommand).ok
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/sbin/purge, /usr/bin/dscacheutil, /usr/bin/killall -HUP mDNSResponder"
        let tmp = "/private/tmp/supurgec_sudoers_\(ProcessInfo.processInfo.processIdentifier)"
        let setupScript = [
            "printf '%s\\n' \(quote(rule)) > \(quote(tmp))",
            "/usr/sbin/chown root:wheel \(quote(tmp))",
            "/bin/chmod 0440 \(quote(tmp))",
            "/usr/sbin/visudo -cf \(quote(tmp)) && /bin/mv -f \(quote(tmp)) \(quote(sudoersPath)) || /bin/rm -f \(quote(tmp))",
            afterInstallCommand
        ].joined(separator: " && ")
        return runAsAdmin(setupScript).ok
    }

    @MainActor
    static func appleScript(_ source: String) -> (NSAppleEventDescriptor?, String?) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, "Betik oluşturulamadı") }
        let result = script.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorMessage] as? String ?? "Bilinmeyen hata")
        }
        return (result, nil)
    }
}
