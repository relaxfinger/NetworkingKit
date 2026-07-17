# NetworkingKit

A small, Swift 6-first network layer for iOS apps. It gives beginners one obvious way to call REST and GraphQL APIs while keeping the implementation safe for modern concurrency.

## Install

In Xcode, choose **File → Add Package Dependencies…**, then enter this repository URL and add the `NetworkingKit` library to your app target. It supports iOS 15+, macOS 13+, tvOS 15+, and watchOS 8+.

Or declare it in another Swift package:

```swift
.package(url: "https://github.com/relaxfinger/NetworkingKit.git", from: "1.0.0")
```

For contributors, `NetworkingKit.xcodeproj` includes a runnable **NetworkingKitDemo** target. Select `NetworkingKitDemo` in Xcode and run it on an iOS Simulator to see REST with Async/Await and Combine; `DemoGraphQL.swift` shows the GraphQL equivalent.

## REST in three lines

```swift
let api = APIClient(baseURL: URL(string: "https://api.example.com")!)
let user: User = try await api.send(.get("users/42"))
```

Send JSON with the same API:

```swift
let newUser: User = try await api.send(
    .json("users", body: CreateUser(name: "Taylor"))
)
```

## Authentication

```swift
let auth = ClosureInterceptor { request in
    var request = request
    request.headers["Authorization"] = "Bearer \(tokenStore.token)"
    return request
}
let api = APIClient(baseURL: baseURL, interceptors: [auth])
```

## Combine

```swift
api.publisher(.get("users/42"), as: User.self)
    .sink(receiveCompletion: { print($0) }, receiveValue: { print($0.name) })
```

## GraphQL

```swift
struct Variables: Codable, Sendable { let id: String }
let operation = GraphQLOperation(
    query: "query User($id: ID!) { user(id: $id) { id name } }",
    variables: Variables(id: "42")
)
let response: GraphQLResponse<UserQuery> = try await api.graphql(operation)
let user = response.data?.user
```

GraphQL servers can return both `data` and `errors`; inspect `response.errors` when partial results are meaningful.

## Principles

- **Swift 6 concurrency:** `APIClient` is an actor; all request configuration is `Sendable`.
- **Typed errors:** distinguish HTTP status, encoding, decoding, cancellation, and transport failures.
- **Testable:** inject a `URLSession` backed by a custom `URLProtocol` in app tests.
- **No dependencies:** Foundation and Combine only.

## License

MIT. See [LICENSE](LICENSE).
