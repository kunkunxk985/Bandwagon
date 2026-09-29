import Foundation

enum JSONValue {
    static func int(_ value: Any?) -> Int {
        switch value {
        case let n as Int: return n
        case let n as Int64: return Int(n)
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }

    static func double(_ value: Any?) -> Double {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }

    static func string(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if value is NSNull || value == nil { return "" }
        if let n = value as? NSNumber { return n.stringValue }
        return String(describing: value ?? "")
    }

    static func bool(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["1", "true", "yes", "on"].contains(s.lowercased())
        default: return defaultValue
        }
    }

    static func object(_ value: Any?) -> [String: Any] {
        if let dict = value as? [String: Any] { return dict }
        if let s = value as? String, let data = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return [:]
    }

    static func array(_ value: Any?) -> [Any] {
        if let arr = value as? [Any] { return arr }
        if let dict = value as? [String: Any] { return Array(dict.values) }
        return []
    }
}
