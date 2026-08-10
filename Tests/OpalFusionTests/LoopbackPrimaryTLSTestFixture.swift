// LoopbackPrimaryTLSTestFixture.swift

import Foundation
import Network
import Security
enum LoopbackPrimaryTLSTestFixture {
    typealias Material = (
        certificateDER: Data,
        localIdentity: sec_identity_t
    )

    static let host = "localhost"
    private static let pkcs12Passphrase = "OpalFusionTests"
    private static let materialCache = LoopbackPrimaryTLSMaterialCache()

    static func loadTrustAnchorCertificateDERs() async throws -> [Data] {
        try await materialCache.loadTrustAnchorCertificateDERs()
    }

    static func makeListenerParameters() async throws -> NWParameters {
        try await materialCache.makeListenerParameters()
    }

    static func makeMaterial() throws -> Material {
        let cleanupDirectory = try prepareServerFiles()
        let keyURL = cleanupDirectory.appendingPathComponent("localhost.key.pem")
        let certificateURL = cleanupDirectory.appendingPathComponent("localhost.cert.pem")
        let pkcs12URL = cleanupDirectory.appendingPathComponent("localhost.identity.p12")

        defer {
            try? FileManager.default.removeItem(at: cleanupDirectory)
        }

        try runOpenSSL(
            [
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-sha256",
                "-days",
                "3650",
                "-subj",
                "/CN=\(host)",
                "-addext",
                "subjectAltName=DNS:\(host)",
                "-keyout",
                keyURL.path,
                "-out",
                certificateURL.path
            ]
        )
        try runOpenSSL(
            [
                "pkcs12",
                "-export",
                "-passout",
                "pass:\(pkcs12Passphrase)",
                "-out",
                pkcs12URL.path,
                "-inkey",
                keyURL.path,
                "-in",
                certificateURL.path
            ]
        )

        let pkcs12Data = try Data(contentsOf: pkcs12URL)
        let certificatePEM = try String(contentsOf: certificateURL, encoding: .utf8)
        let certificateDER = try decodePEM(certificatePEM)
        let importOptions = [
            kSecImportExportPassphrase as String: pkcs12Passphrase
        ] as CFDictionary
        var importedItems: CFArray?
        let importStatus = SecPKCS12Import(
            pkcs12Data as CFData,
            importOptions,
            &importedItems
        )
        guard let importedItems = importedItems as? [[String: Any]],
              let importedItem = importedItems.first
        else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback identity import failed with status \(importStatus)"
            )
        }

        // Current Security.framework versions can return a usable identity dictionary
        // alongside a nonzero import status. The typed identity and the subsequent live
        // sec_identity/TLS handshake remain the authoritative fixture validation.
        guard let identityValue = importedItem[kSecImportItemIdentity as String] else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback identity import did not return an identity (status \(importStatus))"
            )
        }
        let identityObject = identityValue as CFTypeRef
        guard CFGetTypeID(identityObject) == SecIdentityGetTypeID() else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback identity import returned an unexpected item type"
            )
        }
        let identity = identityObject as! SecIdentity
        guard let certificate = SecCertificateCreateWithData(
            nil,
            certificateDER as CFData
        ) else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback certificate could not be materialized"
            )
        }

        guard let localIdentity = sec_identity_create_with_certificates(
            identity,
            [certificate] as CFArray
        ) else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback local identity could not be created"
            )
        }

        return (
            certificateDER: certificateDER,
            localIdentity: localIdentity
        )
    }

    private static func prepareServerFiles() throws -> URL {
        let cleanupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cleanupDirectory,
            withIntermediateDirectories: true
        )
        return cleanupDirectory
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorSummary = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback OpenSSL command failed: \(errorSummary ?? arguments.joined(separator: " "))"
            )
        }
    }

    private static func decodePEM(_ pem: String) throws -> Data {
        let base64 = pem
            .split(separator: "\n")
            .filter { $0.hasPrefix("-----") == false }
            .joined()

        guard let data = Data(base64Encoded: base64) else {
            throw LiveRuntimeTestHarnessError.invalidTLSFixture(
                "TLS loopback certificate fixture could not be decoded"
            )
        }

        return data
    }
}
