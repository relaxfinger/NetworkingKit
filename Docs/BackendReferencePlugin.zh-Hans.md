# 后端 API HTML 文档

NetworkingKit 会静态扫描 Xcode App 的 Swift 源码，生成可搜索的后端 API HTML 文档。文档有一个首页，每个后端服务器各有一个详情页。

每个服务器页包含：

- **配置**表：先读取 NetworkingKit 默认配置，再用 Client 提供且能静态识别的值逐项覆盖，展示最终生效值；
- 按最近 `// MARK: - Feature 名称` 分组的端点；
- Method、Endpoint、Kind、参数、Request 与 Source；
- 可搜索服务器、Feature、端点、参数、Request 和 Source 的搜索框。

包中提供两个 Xcode 插件，请按输出位置选择：

| 插件 | 执行时机 | 输出位置 | 适用场景 |
| --- | --- | --- | --- |
| `BackendReferenceCommandPlugin` | 在 Xcode 手动执行 | `$SRCROOT/Docs/BackendAPIReference/` | 固定保存、提交或分享 HTML 文档 |
| `BackendReferencePlugin` | 每次构建自动执行 | Xcode Derived Data 的插件工作目录 | 不改动工程文件的构建期预览 |

## 开始前准备

1. 在 App 工程中选择 **File → Add Package Dependencies…**，添加 NetworkingKit。
2. 将 `NetworkingKit` library product 添加到定义网络 Client 和 Request 的 target。
3. 等待 Xcode 完成 package resolve。
4. 确保 App 源码中声明了具体的 `NetworkClient` 或 `SharedNetworkClient`，并使用下文的[识别规则](#识别规则)定义请求。

插件只扫描 Swift 源码，不会运行 App，也不会请求后端服务。

## 推荐：`BackendReferenceCommandPlugin`

当 HTML 需要固定保存在 `.xcodeproj` 同级目录、可直接打开、提交、归档或分享给团队时，使用 Command Plugin。

### 在 Xcode 中配置和执行

1. 打开 App 工程，确认左侧 **Package Dependencies** 中存在 `NetworkingKit`。
2. 选择 **File → Packages → Generate Backend API Reference**。
3. 首次执行时，阅读 Xcode 的提示并选择 **Allow Command to Change Files**。该授权是必须的，因为插件需要写入工程目录。
4. 等待命令结束。它会创建或刷新：

   ```text
   $SRCROOT/Docs/BackendAPIReference/index.html
   $SRCROOT/Docs/BackendAPIReference/<服务器名称>.html
   ```

5. 在 Finder 中打开 `Docs/BackendAPIReference/index.html`。需要在 Xcode 中方便查看时，可将 `Docs` 作为文件夹引用加入 navigator；不要把 HTML 加入 App target 的资源。
6. Client、Request、配置或 Feature 标记变动后，重复执行同一个菜单命令即可刷新。

不需要配置 Run Script、package checkout 路径、`--package-path` 或环境变量。Xcode Command Plugin 会直接取得当前 App 工程目录。

### 提交或忽略生成结果

`Docs/BackendAPIReference` 是普通工程输出。若它是需要评审的团队参考文档，可以提交到 Git；若仅供本机使用，可将该目录加入 `.gitignore`。无论哪种方式，都不要把这些 HTML 加入 App bundle。

## 自动预览：`BackendReferencePlugin`

当文档应随每次 Build 自动刷新、但不需要保存到仓库时，使用 Build Tool Plugin。

### 配置到 App Target

1. 在 Xcode navigator 中选择 App 工程。
2. 选择 **App Target**，打开 **Build Phases**。
3. 展开 **Run Build Tool Plug-ins**。
4. 点击 `+`，选择并添加 **BackendReferencePlugin (NetworkingKit)**。
5. Build App。若 Xcode 在 package 更新后提示信任插件，审阅后选择 **Trust & Enable**。
6. 打开 **Report navigator**（⌘9），选择该次 Build 并展开 **Generate backend API reference**。入口文件是该 target 插件工作目录中的 `BackendAPIReference/index.html`，目录位于 Xcode Derived Data。

SwiftPM Build Tool Plugin 受到沙盒限制，不能写入 `$SRCROOT`；因此它无法在 App 根目录创建 `Docs/BackendAPIReference`。这是预期行为，不是配置失败。需要固定目录时请改用 Command Plugin。

## 识别规则

生成器使用静态源码分析。以下结构能得到最完整的文档：

```swift
final class AccountAPIClient: SharedNetworkClient, @unchecked Sendable {
    static let shared = AccountAPIClient()
    let baseURL = URL(string: "https://api.example.com")!
    let session = URLSession.shared
    let configuration = NetworkConfiguration(timeoutInterval: 15)
}

protocol AccountRequest: NetworkRequest where Client == AccountAPIClient {}

// MARK: - Profiles
struct GetProfileRequest: AccountRequest, RestfulRequest {
    let userID: String
    var path: String { "/v1/profiles/\(userID)" }
    var method: HTTPMethod { .get }
}
```

- `NetworkClient` / `SharedNetworkClient` 的 `baseURL` 表示一个后端服务器。
- 绑定到某个具体 Client 的请求协议，会将 Request 关联到对应服务器。
- `RestfulRequest` 和 `GraphQLRequest` 声明会被识别为端点。GraphQL 端点固定为 `/graphql` 和 `POST`；能够静态识别的 `query`、`variables` 与 `operationName` 会展示在参数列中。
- 请求声明上方最近的 `// MARK: - Feature 名称` 用于 Feature 分组。
- Request 的存储属性会列为参数；Client 的 `configuration` 会生成配置表。

扫描器不会执行 Swift 代码。动态 URL、HTTP 方法与复杂表达式会尽量保留源码形式；无法确定时显示为 `<dynamic>`。运行期计算出的最终值不一定能被解析。

## 常见问题

| 现象 | 处理方式 |
| --- | --- |
| **File → Packages** 中没有该命令 | 重新 resolve packages，确认依赖为 NetworkingKit 2.4.3 或更高版本，然后重新打开工程。 |
| Xcode 提示插件被禁用或未信任 | 再次执行命令或构建，在 Xcode 提示中选择 **Trust & Enable** 或 **Allow Command to Change Files**。 |
| Build Tool Plugin 没有生成 `Docs` | 这是正常的：沙盒只允许写入 Derived Data。请改用 `BackendReferenceCommandPlugin`。 |
| 缺少 Request 或 Feature | 检查请求协议是否绑定了具体 Client、是否遵循 `RestfulRequest` / `GraphQLRequest`，以及 `// MARK:` 是否位于请求声明之前。 |
| 值显示为 `<dynamic>` | 尽量使用字面量或可静态解析的值；插件不会执行运行时代码。 |

在非 Xcode 的自动化环境中，可通过 checkout 后的 `BackendReferenceGenerator` 配合 `--source-directory`、`--output-directory` 与 `--stamp` 运行。这是 CI 备用方案；Xcode 中应优先使用 Command Plugin。
