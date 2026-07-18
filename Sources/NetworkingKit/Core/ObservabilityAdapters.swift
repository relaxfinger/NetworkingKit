//
//  ObservabilityAdapters.swift
//  NetworkingKit
//
//  Copyright (c) 2026 NetworkingKit contributors.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import OSLog

/// Writes network lifecycle events to Apple's unified logging system.
public struct OSLogNetworkObserver: NetworkObserving {
    private let logger: Logger

    public init(subsystem: String, category: String = "Networking") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func record(_ event: NetworkEvent) async {
        switch event {
        case let .started(context):
            logger.debug("Started \(context.method.rawValue, privacy: .public) \(context.url.absoluteString, privacy: .public) id=\(context.id, privacy: .public)")
        case let .finished(context, outcome):
            logger.info("Finished id=\(context.id, privacy: .public) status=\(outcome.statusCode ?? 0) duration=\(outcome.duration, format: .fixed(precision: 3))")
        }
    }
}

/// Receives OpenTelemetry-compatible network attributes without adding an SDK dependency.
public protocol OpenTelemetryExporting: Sendable {
    func export(name: String, attributes: [String: String]) async
}

/// Bridges network events into an OpenTelemetry SDK adapter supplied by the app.
public struct OpenTelemetryNetworkObserver: NetworkObserving {
    private let exporter: any OpenTelemetryExporting

    public init(exporter: any OpenTelemetryExporting) { self.exporter = exporter }

    public func record(_ event: NetworkEvent) async {
        switch event {
        case let .started(context):
            await exporter.export(name: "http.request.started", attributes: ["http.request.method": context.method.rawValue, "url.full": context.url.absoluteString, "networkingkit.request_id": context.id])
        case let .finished(context, outcome):
            await exporter.export(name: "http.request.finished", attributes: ["networkingkit.request_id": context.id, "http.response.status_code": String(outcome.statusCode ?? 0), "networkingkit.duration_seconds": String(outcome.duration), "error.type": outcome.error.map { String(describing: type(of: $0)) } ?? ""])
        }
    }
}
