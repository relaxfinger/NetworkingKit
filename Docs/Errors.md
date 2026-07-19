# Errors and localization

[简体中文](Errors.zh-Hans.md) · [Documentation index](README.md)

`NetworkError` is the stable error value exposed by NetworkingKit. UI should show product-owned localized text; diagnostics should use structured fields such as status code and response headers rather than parse a display string.

## Handle structured errors

```swift
do {
    let user = try await GetUserRequest(id: "42").execute()
    show(user)
} catch let error as NetworkError {
    switch error {
    case .cancelled:
        break // Usually no user-facing message.
    case .unauthorized:
        showSignIn()
    case let .http(statusCode, _, _):
        showHTTPFailure(statusCode)
    default:
        showRetryAction()
    }
}
```

Use `CacheMissError` to distinguish an intentional offline-cache miss, and `CircuitOpenError` to distinguish a temporarily protected unhealthy route.

## Localize UI text

Implement `NetworkErrorLocalizing` and add it to `NetworkConfiguration`. The localizer can use the App's localization resources and language policy.

```swift
struct AppErrorLocalizer: NetworkErrorLocalizing {
    func message(for error: NetworkError, locale: Locale) -> String {
        switch error {
        case .unauthorized:
            return String(localized: "network.session_expired", bundle: .main, locale: locale)
        case let .http(statusCode, _, _):
            return String(
                format: String(localized: "network.http_status", bundle: .main, locale: locale),
                statusCode
            )
        case .cancelled:
            return ""
        default:
            return String(localized: "network.unavailable", bundle: .main, locale: locale)
        }
    }
}

let configuration = NetworkConfiguration(errorLocalizer: AppErrorLocalizer())
```

Do not display raw server bodies to users. They are often technical, unstable, and may contain sensitive information. Log structured context only under the App's privacy policy.
