import Foundation

/// Whether the writer has agreed to text leaving the device, and how often to ask.
enum ConsentGate {
    static let alwaysAskKey = "ConsentAlwaysAsk"
    static let agreedKey = "ConsentAgreed"

    /// True when no sheet is needed: the writer agreed once and asked not to
    /// be asked again.
    static var isSettled: Bool {
        UserDefaults.standard.bool(forKey: agreedKey) && !(UserDefaults.standard.object(forKey: alwaysAskKey) as? Bool ?? true)
    }

    static func agree(alwaysAsk: Bool) {
        UserDefaults.standard.set(true, forKey: agreedKey)
        UserDefaults.standard.set(alwaysAsk, forKey: alwaysAskKey)
    }
}
