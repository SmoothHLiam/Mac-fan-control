#if canImport(IOKit)
import Foundation
import IOKit

/// Mirrors the 80-byte `SMCParamStruct` the AppleSMC kernel extension expects.
struct SMCParam {
    typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var mem: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimit = PLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

public struct SMCKeyInfo {
    public let size: UInt32
    public let type: String

    public init(size: UInt32, type: String) {
        self.size = size
        self.type = type
    }
}

public struct FanHardwareInfo: Equatable {
    public let index: Int
    public let minRPM: Double
    public let maxRPM: Double

    public init(index: Int, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

/// Thin wrapper over the AppleSMC user client. Reads work unprivileged; writes need root (see FanHelper).
public final class SMCClient {
    private enum Command: UInt8 {
        case readBytes = 5, writeBytes = 6, keyAtIndex = 8, keyInfo = 9
    }

    private var connection: io_connect_t = 0
    private var infoCache: [String: SMCKeyInfo] = [:]

    public init?() {
        // If this ever fails the Swift layout drifted from the kernel's, and every call would be garbage.
        guard MemoryLayout<SMCParam>.size == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: Low level

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var output = SMCParam()
        var outSize = MemoryLayout<SMCParam>.size
        let r = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParam>.size, &output, &outSize)
        guard r == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    public func keyInfo(_ key: String) -> SMCKeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = SMCParam()
        input.key = SMCCodec.fourCC(key)
        input.data8 = Command.keyInfo.rawValue
        guard let out = call(&input) else { return nil }
        let info = SMCKeyInfo(size: out.keyInfo.dataSize, type: SMCCodec.string(fromFourCC: out.keyInfo.dataType))
        infoCache[key] = info
        return info
    }

    public func keyExists(_ key: String) -> Bool { keyInfo(key) != nil }

    public func readBytes(_ key: String) -> (info: SMCKeyInfo, bytes: [UInt8])? {
        guard let info = keyInfo(key) else { return nil }
        var input = SMCParam()
        input.key = SMCCodec.fourCC(key)
        input.keyInfo.dataSize = info.size
        input.data8 = Command.readBytes.rawValue
        guard let out = call(&input) else { return nil }
        let count = Int(min(info.size, 32))
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(count)) }
        return (info, bytes)
    }

    public func readValue(_ key: String) -> Double? {
        guard let (info, bytes) = readBytes(key) else { return nil }
        return SMCCodec.decode(type: info.type, bytes: bytes)
    }

    @discardableResult
    public func writeValue(_ key: String, _ value: Double) -> Bool {
        guard let info = keyInfo(key), let encoded = SMCCodec.encode(type: info.type, value: value) else { return false }
        var input = SMCParam()
        input.key = SMCCodec.fourCC(key)
        input.keyInfo.dataSize = info.size
        input.data8 = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for (i, b) in encoded.enumerated() where i < 32 { buf[i] = b }
        }
        return call(&input) != nil
    }

    // MARK: Enumeration

    public var keyCount: Int {
        Int(readValue("#KEY") ?? 0)
    }

    public func key(at index: Int) -> String? {
        var input = SMCParam()
        input.data8 = Command.keyAtIndex.rawValue
        input.data32 = UInt32(index)
        guard let out = call(&input) else { return nil }
        return SMCCodec.string(fromFourCC: out.key)
    }

    /// Every temperature-looking key ("T..." returning a plausible float). Done once at startup.
    public func discoverTemperatureKeys() -> [String] {
        var found: [String] = []
        for i in 0..<keyCount {
            guard let key = key(at: i), key.hasPrefix("T"),
                  let info = keyInfo(key), info.type == "flt ",
                  let v = readValue(key), SensorCatalog.isPlausible(v) else { continue }
            found.append(key)
        }
        return found
    }

    // MARK: Fans

    public var fanCount: Int { Int(readValue("FNum") ?? 0) }

    public func fanHardware() -> [FanHardwareInfo] {
        (0..<fanCount).compactMap { i in
            guard let lo = readValue("F\(i)Mn"), let hi = readValue("F\(i)Mx"), hi > lo else { return nil }
            return FanHardwareInfo(index: i, minRPM: lo, maxRPM: hi)
        }
    }

    public func actualRPM(fan: Int) -> Double? { readValue("F\(fan)Ac") }

    // MARK: Fan writes (root only)

    private var forcedTest = false

    /// Puts a fan in manual mode and sets its target. Returns an error description, or nil on success.
    ///
    /// On recent Apple Silicon macOS releases `thermalmonitord` reasserts automatic mode, so if the mode write
    /// doesn't stick we set the `Ftst` diagnostic flag and retry. This path is best-effort: SMC behaviour
    /// differs per chip/OS and should be verified on the target machine.
    public func setManualTarget(fan: Int, rpm: Double) -> String? {
        let mode = "F\(fan)Md", target = "F\(fan)Tg"
        guard keyExists(target) else { return "Fan \(fan) has no target key" }
        if keyExists(mode), readValue(mode) != 1 {
            var engaged = writeValue(mode, 1) && readValue(mode) == 1
            if !engaged, keyExists("Ftst") {
                writeValue("Ftst", 1)
                forcedTest = true
                for _ in 0..<20 {
                    if writeValue(mode, 1), readValue(mode) == 1 { engaged = true; break }
                    usleep(100_000)
                }
            }
            if !engaged { return "Fan \(fan) did not accept manual mode" }
        }
        return writeValue(target, rpm) ? nil : "Could not write target for fan \(fan)"
    }

    public func releaseFan(_ fan: Int) {
        writeValue("F\(fan)Md", 0)
    }

    public func releaseAllFans() {
        for i in 0..<fanCount { releaseFan(i) }
        if forcedTest {
            writeValue("Ftst", 0)
            forcedTest = false
        }
    }
}
#endif
