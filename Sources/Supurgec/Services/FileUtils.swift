import Foundation

enum FileUtils {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }
    static var library: URL { home.appendingPathComponent("Library") }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Disk üzerinde kapladığı gerçek alan (bayt).
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [],
                                    errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Kalıcı olarak siler; açılan alanı döndürür.
    static func remove(_ items: [(url: URL, size: Int64)], progress: ((String) -> Void)? = nil) -> Int64 {
        var freed: Int64 = 0
        for item in items {
            progress?(item.url.path)
            do {
                try fm.removeItem(at: item.url)
                freed += item.size
            } catch {
                let remaining = size(of: item.url)
                freed += max(0, item.size - remaining)
            }
        }
        return freed
    }

    /// Çöp Kutusu'na taşır; başarısız olanları döndürür.
    static func trash(_ urls: [URL]) -> [URL] {
        var failed: [URL] = []
        for u in urls {
            do { try fm.trashItem(at: u, resultingItemURL: nil) } catch { failed.append(u) }
        }
        return failed
    }
}

extension Int64 {
    /// Dosya ve disk alanı için (Finder uyumlu, 1000 tabanlı).
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
    /// RAM için (Etkinlik Monitörü uyumlu, 1024 tabanlı — 16 GB RAM'i 16,00 GB olarak gösterir).
    var formattedMemory: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .memory) }
}

extension Double {
    var formattedBytes: String { Int64(self).formattedBytes }
    var formattedMemory: String { Int64(self).formattedMemory }
}
