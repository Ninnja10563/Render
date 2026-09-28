import Foundation
import CryptoKit

// Read key material from a protected file, never from command-line arguments or logs.
let encoded = try String(contentsOfFile: CommandLine.arguments[1],encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
guard let seed = Data(base64Encoded: encoded),seed.count == 32 else {
    fputs("Invalid update signing key format.\n",stderr); exit(1)
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let plist = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let info = try PropertyListSerialization.propertyList(from: plist,format: nil) as? [String: Any]
guard info?["SUPublicEDKey"] as? String == key.publicKey.rawRepresentation.base64EncodedString() else {
    fputs("Update signing key does not match the application's public key.\n",stderr); exit(1)
}
