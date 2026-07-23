# 后端 API HTML 索引

NetworkingKit 同时提供 Build Tool Plugin 和 Command Plugin，用于扫描 App 的 Swift 源码并生成后端服务器、Feature、端点、请求参数与网络配置的 HTML 索引。

## 推荐：Command Plugin 写入 Docs

需要在 App 根目录保留可浏览的 HTML 时，使用 `BackendReferenceCommandPlugin`。它会生成：

```text
$SRCROOT/Docs/BackendAPIReference/index.html
```

在 Xcode 中执行：

1. 选择 **File → Packages → Generate Backend API Reference**。
2. 第一次执行时，审阅插件并选择 **Allow Command to Change Files**，授权它写入项目的 `Docs/` 目录。
3. 在 Finder 或 Xcode 中打开 `Docs/BackendAPIReference/index.html`。

Command Plugin 使用 XcodeProjectPlugin API 定位当前 App 工程，不需要配置 `--package-path`、Run Script 或环境变量。适合在需要时刷新并提交、归档或分享这份文档。

## Build Tool Plugin：构建产物预览

### Xcode 配置步骤

1. 使用 **File → Add Package Dependencies…** 将 `NetworkingKit` 添加到工程。
2. 选中 App Target，打开 **Build Phases**。
3. 在 **Run Build Tool Plug-ins** 区域点击 `+`，选择 `BackendReferencePlugin`。
4. 直接 Build App。构建日志会显示 **Generate backend API reference**。
5. 在 Xcode Report navigator 中展开该构建步骤；HTML 位于该 Target 对应的 Derived Data 插件输出目录，入口文件为 `BackendAPIReference/index.html`。在 Finder 中打开该目录即可浏览文档。

Build Tool Plugin 受 SwiftPM 沙盒保护，只能写入 Derived Data 的插件工作目录，不能写回 App 的源码根目录。它适合每次构建时自动生成预览；若需要固定的 Docs 文件，请使用上面的 Command Plugin。

## 备用：导出到 App 根目录

只有无法从 Xcode 运行 Command Plugin、但仍需在自动化环境导出 HTML 时，才使用 Run Script Build Phase。该备用方式需要为 Package checkout 提供路径：

```sh
swift run --package-path "$NETWORKING_KIT_CHECKOUT" BackendReferenceGenerator \
  --source-directory "$SRCROOT" \
  --output-directory "$SRCROOT/BackendAPIReference" \
  --stamp "$DERIVED_FILE_DIR/backend-reference-export.stamp"
```

配置步骤：

1. 在 Scheme 或 CI 中定义 `NETWORKING_KIT_CHECKOUT`，值为 `NetworkingKit` 本地 checkout 的绝对路径。
2. 在 App Target 的 **Build Phases** 点击 `+ → New Run Script Phase`，并将该步骤放在编译步骤之后。
3. 粘贴上面的脚本，Build 一次。
4. 打开 `$SRCROOT/BackendAPIReference/index.html`。该目录只包含开发文档，不应加入 App bundle；如不需要提交，可加入 `.gitignore`。

如果只需要在开发和 CI 中查看文档，请保持仅使用 Build Tool Plugin；Run Script 是输出位置必须为 App 根目录时的次要方案。

## 识别规则

- `NetworkClient` / `SharedNetworkClient` 的 `baseURL` 表示一个后端服务器。
- `protocol AppNetworkRequest: NetworkRequest where Client == AppNetworkClient` 将请求关联至服务器。
- `RestfulRequest` 和 `GraphQLRequest` 会被识别为端点。
- 请求声明上方最近的 `// MARK: - Feature 名称` 作为 Feature 分组。
- 请求的存储属性列为参数，客户端 `configuration` 会在服务器页展示。

```swift
// MARK: - Characters
struct GetCharacterRequest: AppNetworkRequest, RestfulRequest {
    private let id: String
    var path: String { "/api/character/\(id)" }
    var method: HTTPMethod { .get }
}
```

静态扫描不会执行 Swift 代码。动态 URL、HTTP 方法及复杂表达式会保留源码形式或显示为 `<dynamic>`。
