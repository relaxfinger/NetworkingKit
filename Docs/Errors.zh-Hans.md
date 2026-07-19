# 错误与本地化

[English](Errors.md) · [文档索引](README.zh-Hans.md)

`NetworkError` 是 NetworkingKit 对外暴露的稳定错误值。UI 应显示产品自己控制的本地化文案；诊断应读取状态码、响应 Header 等结构化字段，而不是解析展示文案。

## 处理结构化错误

```swift
do {
    let user = try await GetUserRequest(id: "42").execute()
    show(user)
} catch let error as NetworkError {
    switch error {
    case .cancelled:
        break // 通常不提示用户。
    case .unauthorized:
        showSignIn()
    case let .http(statusCode, _, _):
        showHTTPFailure(statusCode)
    default:
        showRetryAction()
    }
}
```

使用 `CacheMissError` 区分明确的离线缓存未命中；使用 `CircuitOpenError` 区分被暂时保护的异常路由。

## 本地化 UI 文案

实现 `NetworkErrorLocalizing` 并配置到 `NetworkConfiguration`。本地化器可使用 App 的本地化资源与语言策略。

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

不要把原始服务端 body 直接展示给用户。它通常技术性强、格式不稳定，并可能含有敏感信息。记录结构化上下文时也要遵守 App 的隐私策略。
