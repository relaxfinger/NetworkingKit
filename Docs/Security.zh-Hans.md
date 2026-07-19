# 传输安全与 Pinning

[English](Security.md) · [文档索引](README.zh-Hans.md)

系统 TLS 信任是多数 App 正确的默认选择。只有明确的安全要求存在，并且服务具备经测试的证书轮换流程时才使用 pinning。错误的 pin 会让所有用户无法访问后端。

## 证书 Pinning

`CertificatePinningEvaluator` 会在系统信任成功后，对指定 Host 比对叶子证书的 DER 数据。

```swift
let evaluator = CertificatePinningEvaluator(pinnedCertificates: [
    "api.example.com": [currentCertificateDER, nextCertificateDER]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

为需要 pinning 的后端使用专用 Session。没有配置 pin 的 Host 由 evaluator 保持系统默认处理。轮换期间至少保留当前和下一张证书的 pin。

## 公钥哈希 Pinning

`PublicKeyHashPinningEvaluator` 比对叶子证书公钥 bytes 的 SHA-256 哈希。当证书可能更新但公钥保持稳定时适用。

```swift
let evaluator = PublicKeyHashPinningEvaluator(pinnedHashes: [
    "api.example.com": [currentPublicKeyHash, backupPublicKeyHash]
])
let delegate = ServerTrustSessionDelegate(evaluator: evaluator)
let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
```

Pin 是 `Data` 值。应在受控的构建/发布流程中生成和验证，不要在运行时从同一条不可信网络链路下载新 pin。

## 运维清单

- 每次证书或密钥变更前保留备用 pin。
- 生产轮换前在预发环境验证下一枚 pin。
- 将 pinning 失败与普通传输失败分开监控。
- 为 pin 丢失或泄露准备紧急发布流程。
- 将 pinning 限制在确实需要它的后端专用 Session。

Pinning 只加强传输信任的一部分，不能替代 HTTPS、安全 Token 存储、请求授权、输入校验或隐私审查。
