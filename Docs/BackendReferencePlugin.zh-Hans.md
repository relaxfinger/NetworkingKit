# 后端 API HTML 索引

`BackendReferencePlugin` 会在每次编译 App Target 时扫描 Swift 源码，生成后端服务器、Feature、端点、请求参数与网络配置的 HTML 索引。默认推荐使用 Build Tool Plugin：无需维护 `--package-path` 或额外脚本，且始终与本次构建使用相同的源码。

## 推荐：Build Tool Plugin

### Xcode 配置步骤

1. 使用 **File → Add Package Dependencies…** 将 `NetworkingKit` 添加到工程。
2. 选中 App Target，打开 **Build Phases**。
3. 在 **Run Build Tool Plug-ins** 区域点击 `+`，选择 `BackendReferencePlugin`。
4. 直接 Build App。构建日志会显示 **Generate backend API reference**。
5. 在 Xcode Report navigator 中展开该构建步骤；HTML 位于该 Target 对应的 Derived Data 插件输出目录，入口文件为 `BackendAPIReference/index.html`。在 Finder 中打开该目录即可浏览文档。

Build Tool Plugin 受 SwiftPM 沙盒保护，只能写入 Derived Data 的插件工作目录，不能写回 App 的源码根目录。这是它无需路径配置、可安全在本地与 CI 自动运行的原因。

## 备用：导出到 App 根目录

只有需要将 HTML 固定保存为 `$SRCROOT/BackendAPIReference/`、提交到制品库或交付给非 Xcode 用户时，才在 App Target 最后添加一个 **Run Script Build Phase**。该备用方式需要为 Package checkout 提供路径：

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
