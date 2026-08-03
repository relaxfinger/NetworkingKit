import Foundation
@testable import BackendReferenceGeneratorCore
import XCTest

final class BackendReferenceGeneratorTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/FixtureApp", isDirectory: true)

    func testParsesLiteralServerAndMarkedRESTEndpoint() {
        let documents = [
            document("Networking/APIClient.swift", """
            import Foundation
            import NetworkingKit

            private enum AccountConstants {
                private static let timeout = 12
            }

            final class AccountAPIClient: SharedNetworkClient {
                let baseURL: URL = URL(string: "https://api.example.com")!
                let session = URLSession.shared
                let defaultProfile = NetworkClientProfile(
                    configuration: NetworkConfiguration(timeoutInterval: AccountConstants.timeout)
                )
            }

            protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}
            """),
            document("Features/Profile/ProfileRequests.swift", """
            import NetworkingKit

            // MARK: - Profiles
            struct GetProfileRequest: AccountRequest, RestfulRequest {
                typealias Response = Profile
                let userID: String

                var path: String { "/v1/profile" }
                var method: HTTPMethod { .get }
            }
            """)
        ]

        let servers = BackendReferenceGenerator.parseServers(documents)
        let endpoints = BackendReferenceGenerator.parseEndpoints(
            documents,
            protocolClients: BackendReferenceGenerator.parseProtocolClients(documents),
            root: root
        )

        XCTAssertEqual(servers.map(\.name), ["AccountAPIClient"])
        XCTAssertEqual(servers.first?.baseURL, "https://api.example.com")
        XCTAssertEqual(servers.first?.configuration.first(where: { $0.0 == "timeoutInterval" })?.1, "12")
        XCTAssertEqual(endpoints.map(\.name), ["GetProfileRequest"])
        XCTAssertEqual(endpoints.first?.feature, "Profiles")
        XCTAssertEqual(endpoints.first?.method, "GET")
        XCTAssertEqual(endpoints.first?.path, "/v1/profile")
        XCTAssertEqual(endpoints.first?.parameters, ["userID: String"])
    }

    func testParsesConfigurationFromMultilineDefaultProfile() {
        let source = """
        final class APIClient: SharedNetworkClient {
            let baseURL = URL(string: "https://api.example.com")!
            let session = URLSession.shared
            let defaultProfile = NetworkClientProfile(
                interceptors: [RequestIDInterceptor()],
                authentication: nil,
                configuration: NetworkConfiguration(
                    timeoutInterval: 9,
                    retryPolicy: RetryPolicy(maxAttempts: 4)
                )
            )
        }
        """

        let servers = BackendReferenceGenerator.parseServers([
            document("Networking/APIClient.swift", source)
        ])

        XCTAssertTrue(
            BackendReferenceGenerator.defaultProfileConfiguration(in: source)
                .contains("timeoutInterval: 9")
        )

        XCTAssertEqual(
            servers.first?.configuration.first(where: { $0.0 == "timeoutInterval" })?.1,
            "9"
        )
        XCTAssertTrue(
            servers.first?.configuration
                .first(where: { $0.0 == "retryPolicy" })?.1
                .contains("maxAttempts: 4") == true
        )
    }

    func testResolvesEndpointURLSplitFromStaticConfiguration() {
        let documents = [
            document("BandUpSpeaking/Networking/BandUpAPIClient.swift", """
            import Foundation
            import NetworkingKit

            nonisolated final class BandUpAPIClient: SharedNetworkClient, @unchecked Sendable {
                static let shared = BandUpAPIClient()

                let baseURL = BandUpAPIEndpoint.feedbackBaseURL
                let session = URLSession.shared
                let defaultProfile = NetworkClientProfile(
                    configuration: NetworkConfiguration(timeoutInterval: BandUpAPIEndpoint.timeoutSeconds)
                )
            }

            nonisolated protocol BandUpAPIRequest: NetworkRequest where Client == BandUpAPIClient {}
            """),
            document("BandUpSpeaking/Networking/BandUpAPIEndpoint.swift", """
            import Foundation

            nonisolated enum BandUpAPIEndpoint {
                private static let feedbackEndpointURLStringKey = "BandUpFeedbackEndpointURL"
                private static let defaultFeedbackEndpointURLString = "https://xcbyvombxwnxuxydhfcj.supabase.co/functions/v1/generate-feedback"
                private static let defaultFeedbackEndpointURL = URL(string: defaultFeedbackEndpointURLString)!

                static let timeoutSeconds: TimeInterval = 30

                static var feedbackEndpointURLString: String {
                    Bundle.main.object(forInfoDictionaryKey: feedbackEndpointURLStringKey) as? String ?? defaultFeedbackEndpointURLString
                }

                static var feedbackEndpointURL: URL? {
                    URL(string: feedbackEndpointURLString)
                }

                static var feedbackBaseURL: URL {
                    splitEndpointURL(resolvedFeedbackEndpointURL).baseURL
                }

                static var feedbackPath: String {
                    splitEndpointURL(resolvedFeedbackEndpointURL).path
                }

                private static var resolvedFeedbackEndpointURL: URL {
                    feedbackEndpointURL ?? defaultFeedbackEndpointURL
                }

                private static func splitEndpointURL(_ endpointURL: URL) -> (baseURL: URL, path: String) {
                    let path = endpointURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return (URL(string: endpointURL.absoluteString)!, path)
                }
            }
            """),
            document("BandUpSpeaking/Features/Feedback/Services/RemoteFeedbackService.swift", """
            import NetworkingKit

            nonisolated private struct GenerateFeedbackRequest: BandUpAPIRequest, RestfulRequest {
                typealias Response = RemoteFeedbackResponse
                let body: RemoteFeedbackRequest

                var path: String { BandUpAPIEndpoint.feedbackPath }
                var method: HTTPMethod { .post }
            }
            """)
        ]

        let servers = BackendReferenceGenerator.parseServers(documents)
        let endpoints = BackendReferenceGenerator.parseEndpoints(
            documents,
            protocolClients: BackendReferenceGenerator.parseProtocolClients(documents),
            root: root.appendingPathComponent("BandUpSpeaking")
        )

        XCTAssertEqual(servers.first?.name, "BandUpAPIClient")
        XCTAssertEqual(servers.first?.baseURL, "https://xcbyvombxwnxuxydhfcj.supabase.co")
        XCTAssertEqual(servers.first?.configuration.first(where: { $0.0 == "timeoutInterval" })?.1, "30")
        XCTAssertEqual(endpoints.first?.feature, "Feedback")
        XCTAssertEqual(endpoints.first?.method, "POST")
        XCTAssertEqual(endpoints.first?.path, "functions/v1/generate-feedback")
    }

    func testResolvesInterpolatedStaticPathAndFormatsDynamicSegments() {
        let documents = [
            document("BandUpSpeaking/Networking/BandUpAPIClient.swift", """
            import Foundation
            import NetworkingKit

            nonisolated final class BandUpAPIClient: SharedNetworkClient, @unchecked Sendable {
                let baseURL = BandUpAPIEndpoint.feedbackBaseURL
                let session = URLSession.shared
                let defaultProfile = NetworkClientProfile(
                    configuration: NetworkConfiguration(timeoutInterval: BandUpAPIEndpoint.timeoutSeconds)
                )
            }

            nonisolated protocol BandUpAPIRequest: NetworkRequest where Client == BandUpAPIClient {}
            """),
            document("BandUpSpeaking/Networking/BandUpAPIEndpoint.swift", """
            import Foundation

            nonisolated enum BandUpAPIEndpoint {
                private static let defaultFeedbackEndpointURLString = "https://xcbyvombxwnxuxydhfcj.supabase.co/functions/v1/generate-feedback"
                private static let defaultFeedbackEndpointURL = URL(string: defaultFeedbackEndpointURLString)!
                static let timeoutSeconds: TimeInterval = 30

                static var feedbackBaseURL: URL {
                    splitEndpointURL(defaultFeedbackEndpointURL).baseURL
                }

                static var feedbackPath: String {
                    splitEndpointURL(defaultFeedbackEndpointURL).path
                }

                private static func splitEndpointURL(_ endpointURL: URL) -> (baseURL: URL, path: String) {
                    let path = endpointURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    return (URL(string: endpointURL.absoluteString)!, path)
                }
            }
            """),
            document("BandUpSpeaking/Networking/FeedbackHistoryService.swift", """
            import Foundation
            import NetworkingKit

            nonisolated private struct GenerateFeedbackRequest: BandUpAPIRequest, RestfulRequest {
                typealias Response = RemoteFeedbackResponse
                let body: RemoteFeedbackRequest

                var path: String { "\\(BandUpAPIEndpoint.feedbackPath)/feedback" }
                var method: HTTPMethod { .post }
            }

            nonisolated private struct FeedbackHistoryDetailRequest: BandUpAPIRequest, RestfulRequest {
                typealias Response = RemoteFeedbackHistoryDetail
                let id: UUID

                var path: String { "\\(BandUpAPIEndpoint.feedbackPath)/feedback-history/\\(id.uuidString)" }
                var method: HTTPMethod { .get }
            }
            """)
        ]

        let endpoints = BackendReferenceGenerator.parseEndpoints(
            documents,
            protocolClients: BackendReferenceGenerator.parseProtocolClients(documents),
            root: root.appendingPathComponent("BandUpSpeaking")
        )
        let paths = Dictionary(uniqueKeysWithValues: endpoints.map { ($0.name, $0.path) })

        XCTAssertEqual(
            paths["GenerateFeedbackRequest"],
            "functions/v1/generate-feedback/feedback"
        )
        XCTAssertEqual(
            paths["FeedbackHistoryDetailRequest"],
            "functions/v1/generate-feedback/feedback-history/{id}"
        )
        XCTAssertFalse(paths.values.contains { $0.contains(#"\("#) })
    }

    func testUsesSourcePathFeatureWhenNoMarkExists() {
        let sourceURL = root.appendingPathComponent("Features/Billing/BillingRequests.swift")
        let source = """
        import NetworkingKit

        struct CreateCheckoutRequest: BillingRequest, RestfulRequest {
            typealias Response = Checkout
            var path: String { "/v1/checkout" }
            var method: HTTPMethod { .post }
        }
        """

        XCTAssertEqual(
            BackendReferenceGenerator.feature(before: source.count, in: source, sourceURL: sourceURL, root: root),
            "Billing"
        )
    }

    func testCapturesGraphQLRequestInputs() {
        let documents = [
            document("Networking/StoreAPIClient.swift", """
            import Foundation
            import NetworkingKit

            struct StoreAPIClient: NetworkClient {
                let baseURL = URL(string: "https://store.example.com")!
                let session = URLSession.shared
                let defaultProfile = NetworkClientProfile()
            }

            protocol StoreRequest: NetworkRequest where Client == StoreAPIClient {}
            """),
            document("Features/Catalog/CatalogRequests.swift", """
            import NetworkingKit

            struct ProductQueryRequest: StoreRequest, GraphQLRequest {
                typealias Response = Product
                let sku: String

                var query: String {
                    \"\"\"
                    query Product($sku: String!) {
                      product(sku: $sku) { id name }
                    }
                    \"\"\"
                }

                var variables: [String: AnyEncodable] {
                    ["sku": AnyEncodable(sku)]
                }
            }
            """)
        ]

        let endpoints = BackendReferenceGenerator.parseEndpoints(
            documents,
            protocolClients: BackendReferenceGenerator.parseProtocolClients(documents),
            root: root
        )

        XCTAssertEqual(endpoints.first?.requestKind, "GraphQL")
        XCTAssertEqual(endpoints.first?.method, "POST")
        XCTAssertEqual(endpoints.first?.path, "/graphql")
        XCTAssertTrue(endpoints.first?.parameters.contains(where: { $0.hasPrefix("query:") }) == true)
        XCTAssertTrue(endpoints.first?.parameters.contains(where: { $0.hasPrefix("variables:") }) == true)
    }

    func testCoalescedStaticExpressionsPreferResolvableLeftSide() {
        let documents = [
            document("Networking/APIEndpoint.swift", """
            enum APIEndpoint {
                static let primary = "https://primary.example.com"
                static let fallback = "https://fallback.example.com"
                static var baseURL: URL {
                    URL(string: primary) ?? URL(string: fallback)!
                }
            }
            """)
        ]

        XCTAssertEqual(
            BackendReferenceGenerator.resolveURLExpression("APIEndpoint.baseURL", in: documents),
            "https://primary.example.com"
        )
    }

    private func document(_ path: String, _ source: String) -> (URL, String) {
        (root.appendingPathComponent(path), source)
    }
}
