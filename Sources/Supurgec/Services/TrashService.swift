import Foundation
import AppKit

enum TrashState: Equatable {
    case loading
    case empty
    case items(count: Int, bytes: Int64)
    case permissionNeeded
}

enum TrashService {
    /// Uygulamaya Tam Disk Erişimi verilip verilmediğini doğrudan korumalı dizin üzerinden test eder.
    nonisolated static func hasFullDiskAccess() -> Bool {
        let trashPath = FileUtils.home.appendingPathComponent(".Trash").path
        if (try? FileManager.default.contentsOfDirectory(atPath: trashPath)) != nil {
            return true
        }
        let safariPath = FileUtils.library.appendingPathComponent("Safari").path
        if FileManager.default.fileExists(atPath: safariPath),
           (try? FileManager.default.contentsOfDirectory(atPath: safariPath)) != nil {
            return true
        }
        return false
    }

    /// Hem doğrudan dosya sistemi hem de Finder üzerinden Çöp Kutusu doluluğunu doğru okur.
    static func inspect() async -> TrashState {
        let trashURL = FileUtils.home.appendingPathComponent(".Trash")

        if let directItems = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []) {
            let visible = directItems.filter { $0.lastPathComponent != ".DS_Store" }
            if visible.isEmpty { return .empty }
            let total = await Task.detached(priority: .utility) {
                visible.reduce(Int64(0)) { $0 + FileUtils.size(of: $1) }
            }.value
            return .items(count: visible.count, bytes: total)
        }

        return await MainActor.run {
            let script = """
            tell application "Finder"
                set c to count of items of trash
                if c is 0 then return "0|0"
                set totalBytes to 0
                repeat with it in items of trash
                    try
                        set s to physical size of it
                        if s is not missing value then set totalBytes to totalBytes + s
                    end try
                end repeat
                return (c as string) & "|" & (totalBytes as string)
            end tell
            """
            let (desc, err) = Shell.appleScript(script)
            if err != nil { return .permissionNeeded }
            guard let raw = desc?.stringValue else { return .permissionNeeded }
            let parts = raw.split(separator: "|")
            let count = parts.first.flatMap { Int($0) } ?? 0
            let bytes = parts.count > 1 ? (Int64(Double(parts[1]) ?? 0)) : 0
            if count == 0 { return .empty }
            return .items(count: count, bytes: bytes)
        }
    }

    /// Çöp Kutusu'nu boşaltır.
    static func empty() async -> Bool {
        let trashURL = FileUtils.home.appendingPathComponent(".Trash")
        if let directItems = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []) {
            await Task.detached(priority: .userInitiated) {
                for item in directItems where item.lastPathComponent != ".DS_Store" {
                    try? FileManager.default.removeItem(at: item)
                }
            }.value
            return true
        }

        return await MainActor.run {
            let (_, err) = Shell.appleScript("tell application \"Finder\" to empty trash")
            return err == nil
        }
    }
}
