import Foundation

/// Pure encode/decode helpers for AppleSMC values. No IOKit, so this is unit-testable anywhere.
public enum SMCCodec {
    public static func fourCC(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for b in s.utf8.prefix(4) { v = (v << 8) | UInt32(b) }
        return v
    }

    public static func string(fromFourCC v: UInt32) -> String {
        let bytes: [UInt8] = [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Decodes the SMC data types we care about. Apple Silicon reports floats ("flt ") little-endian;
    /// the integer / fixed-point types are big-endian.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let f = Float(bitPattern: raw)
            return f.isFinite ? Double(f) : nil
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "si8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(Int8(bitPattern: bytes[0]))
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1])))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        default:
            return nil
        }
    }

    /// Encodes `value` for writing. Returns nil for types we don't know how to write.
    public static func encode(type: String, value: Double) -> [UInt8]? {
        guard value.isFinite else { return nil }
        switch type {
        case "flt ":
            let raw = Float(value).bitPattern
            return [UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF), UInt8((raw >> 16) & 0xFF), UInt8((raw >> 24) & 0xFF)]
        case "ui8 ":
            guard value >= 0, value <= 255 else { return nil }
            return [UInt8(value)]
        case "ui16":
            guard value >= 0, value <= 65535 else { return nil }
            let v = UInt16(value)
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        case "fpe2":
            guard value >= 0, value * 4 <= 65535 else { return nil }
            let v = UInt16(value * 4)
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        default:
            return nil
        }
    }
}
