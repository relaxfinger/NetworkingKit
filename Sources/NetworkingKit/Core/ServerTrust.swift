//
//  ServerTrust.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Security

/// Evaluates a server trust challenge for an app-owned URLSession.
public protocol ServerTrustEvaluating: Sendable {
    func evaluate(_ trust: SecTrust, host: String) -> Bool
}

/// Pins leaf certificate DER data for selected hosts.
public struct CertificatePinningEvaluator: ServerTrustEvaluating {
    public let pinnedCertificates: [String: Set<Data>]
    public init(pinnedCertificates: [String: Set<Data>]) { self.pinnedCertificates = pinnedCertificates }
    public func evaluate(_ trust: SecTrust, host: String) -> Bool {
        guard let pins = pinnedCertificates[host] else { return true }
        guard SecTrustEvaluateWithError(trust, nil), let certificate = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = certificate.first else { return false }
        return pins.contains(SecCertificateCopyData(leaf) as Data)
    }
}

/// URLSession delegate that applies a supplied server-trust evaluator.
public final class ServerTrustSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let evaluator: any ServerTrustEvaluating
    public init(evaluator: any ServerTrustEvaluating) { self.evaluator = evaluator }
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        let isTrusted = evaluator.evaluate(trust, host: challenge.protectionSpace.host)
        completionHandler(isTrusted ? .useCredential : .cancelAuthenticationChallenge, isTrusted ? URLCredential(trust: trust) : nil)
    }
}
