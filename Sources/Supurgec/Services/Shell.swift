import Foundation
import Darwin

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
    /// 1) Önce kullanıcı alanı bellek baskısı darbesiyle (inactive sayfaları sıkıştırıcıya iterek) ve malloc/URLCache
    ///    temizliğiyle pasif uygulama sayfalarını sıkıştırır.
    /// 2) Ardından çekirdek disk/dosya/purgeable önbelleklerini (/usr/sbin/purge) tamamen boşaltır.
    static func freeRAMPasswordlessOrSetup() async -> Bool {
        URLCache.shared.removeAllCachedResponses()
        let fast = await Task.detached(priority: .userInitiated) { () -> Bool in
            Self.reclaimInactivePagesPulse()
            let r = Self.run("/usr/bin/sudo", ["-n", "/usr/sbin/purge"])
            if r.status == 0 {
                usleep(250_000)
                return true
            }
            return false
        }.value
        if fast { return true }
        let ok = await installHelperAndRun(afterInstallCommand: "/usr/sbin/purge")
        if ok {
            await Task.detached(priority: .userInitiated) {
                Self.reclaimInactivePagesPulse()
                _ = Self.run("/usr/bin/sudo", ["-n", "/usr/sbin/purge"])
                usleep(250_000)
            }.value
        }
        return ok
    }

    /// Pasif (inactive) anonim bellek sayfalarını macOS VM sıkıştırıcısına (compressor) aktarmak ve
    /// boşta bekleyen önbellek sayfalarını tahliye etmek için kısa süreli (~180ms) güvenli bellek darbesi uygular.
    nonisolated private static func reclaimInactivePagesPulse() {
        malloc_zone_pressure_relief(nil, 0)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let pageSize = Int(sysconf(_SC_PAGESIZE))
        let inactiveBytes = Int64(stats.inactive_count) * Int64(pageSize)
        let freeBytes = Int64(stats.free_count) * Int64(pageSize)
        // Yalnızca kayda değer pasif bellek varsa, güvenli bir dilimi (en fazla 1.5 GB) hızla dokunup serbest bırak
        let targetBytes = min(max(inactiveBytes / 2, freeBytes / 2), 1536 * 1024 * 1024)
        guard targetBytes >= 128 * 1024 * 1024 else { return }

        let chunkSize = 64 * 1024 * 1024
        let chunkCount = max(1, Int(targetBytes) / chunkSize)
        var chunks: [UnsafeMutableRawPointer] = []
        chunks.reserveCapacity(chunkCount)

        for _ in 0..<chunkCount {
            guard let ptr = mmap(nil, chunkSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
                  ptr != MAP_FAILED else { break }
            let bytePtr = ptr.assumingMemoryBound(to: UInt8.self)
            var offset = 0
            while offset < chunkSize {
                bytePtr[offset] = 1
                offset += pageSize
            }
            chunks.append(ptr)
        }
        for ptr in chunks {
            munmap(ptr, chunkSize)
        }
        malloc_zone_pressure_relief(nil, 0)
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
