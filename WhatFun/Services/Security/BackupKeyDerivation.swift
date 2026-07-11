import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum BackupKeyDerivationError: Error, Equatable, LocalizedError {
    case emptyPassphrase
    case invalidSalt
    case randomGenerationFailed(OSStatus)
    case derivationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            "Enter a passphrase for the encrypted private-feed block."
        case .invalidSalt:
            "The backup encryption salt is invalid."
        case let .randomGenerationFailed(status):
            "Secure random generation failed with status \(status)."
        case let .derivationFailed(status):
            "Passphrase key derivation failed with status \(status)."
        }
    }
}
nonisolated enum BackupKeyDerivation {
    static let recommendedIterations: UInt32 = 310_000
    static let saltByteCount = 16
    static let keyByteCount = 32

    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: saltByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw BackupKeyDerivationError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    static func deriveKey(
        passphrase: String,
        salt: Data,
        iterations: UInt32 = recommendedIterations
    ) throws -> SymmetricKey {
        let password = Data(passphrase.utf8)
        guard !password.isEmpty else { throw BackupKeyDerivationError.emptyPassphrase }
        guard salt.count >= 8 else { throw BackupKeyDerivationError.invalidSalt }

        var derived = [UInt8](repeating: 0, count: keyByteCount)
        let status: Int32 = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derived,
                    derived.count
                )
            }
        }
        guard status == kCCSuccess else {
            throw BackupKeyDerivationError.derivationFailed(status)
        }
        return SymmetricKey(data: derived)
    }
}
