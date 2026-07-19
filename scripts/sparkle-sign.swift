// EdDSA signing for Sparkle appcasts, no Sparkle tooling required.
//   swift scripts/sparkle-sign.swift keygen        prints the public key, writes the private seed
//   swift scripts/sparkle-sign.swift sign <file>   prints edSignature and length for the appcast
import CryptoKit
import Foundation

let keyPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".slingshot-sparkle-key")

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "keygen":
    if FileManager.default.fileExists(atPath: keyPath.path) {
        let seed = try Data(contentsOf: keyPath)
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        print("existing public key: \(key.publicKey.rawRepresentation.base64EncodedString())")
    } else {
        let key = Curve25519.Signing.PrivateKey()
        try key.rawRepresentation.write(to: keyPath, options: .completeFileProtection)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath.path)
        print("public key: \(key.publicKey.rawRepresentation.base64EncodedString())")
        print("private seed written to \(keyPath.path). Back it up; losing it strands every installed copy.")
    }
case "sign":
    guard args.count > 2 else { fatalError("usage: sparkle-sign.swift sign <file>") }
    let seed = try Data(contentsOf: keyPath)
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    let payload = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let signature = try key.signature(for: payload)
    print("sparkle:edSignature=\"\(signature.base64EncodedString())\" length=\"\(payload.count)\"")
default:
    fatalError("usage: sparkle-sign.swift keygen | sign <file>")
}
