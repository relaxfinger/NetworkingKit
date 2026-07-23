# Backend API HTML reference

NetworkingKit can statically scan an Xcode app's Swift source and generate searchable HTML documentation for its backend integration. The documentation has an index page and one page per backend server.

Each server page contains:

- a **Configuration** table with final effective values: NetworkingKit defaults, overridden by the values provided by the Client where they are statically discoverable;
- endpoints grouped by the closest `// MARK: - Feature name` declaration;
- method, endpoint, request kind, stored-property parameters, request type, and source file;
- a browser-side search field for servers, features, endpoints, parameters, request types, and source files.

The package offers two Xcode plugins. Choose the output behaviour that matches the workflow.

| Plugin | Run it when | Output | Best for |
| --- | --- | --- | --- |
| `BackendReferenceCommandPlugin` | Manually from Xcode | `$SRCROOT/Docs/BackendAPIReference/` | A permanent, shareable, commit-ready document |
| `BackendReferencePlugin` | Automatically on every build | Xcode Derived Data plugin work directory | A build-time preview without changing the project |

## Before you begin

1. Add NetworkingKit to the App project with **File → Add Package Dependencies…**.
2. Add the `NetworkingKit` library product to the target that contains the networking definitions.
3. Resolve package versions and wait for Xcode to finish preparing packages.
4. Ensure the App code declares concrete `NetworkClient` or `SharedNetworkClient` types and request types as described in [Recognition rules](#recognition-rules).

The plugins scan Swift source; they do not run the App or call a backend.

## Recommended: `BackendReferenceCommandPlugin`

Use this plugin when `Docs/BackendAPIReference` should stay beside the `.xcodeproj` and can be opened, committed, copied to CI artifacts, or shared with the team.

### Configure and run it in Xcode

1. Open the App project in Xcode and confirm `NetworkingKit` appears under **Package Dependencies**.
2. Choose **File → Packages → Generate Backend API Reference**.
3. On the first run, inspect the prompt and choose **Allow Command to Change Files**. The permission is required because this command writes inside the project directory.
4. Wait for the command to finish. It creates or refreshes:

   ```text
   $SRCROOT/Docs/BackendAPIReference/index.html
   $SRCROOT/Docs/BackendAPIReference/<ServerName>.html
   ```

5. In Finder, open `Docs/BackendAPIReference/index.html`. You may add `Docs` to the Xcode project navigator as a folder reference if convenient; do not add the HTML files to the App target's resources.
6. Run the same menu command whenever clients, request definitions, configuration, or Feature markers change.

No Run Script phase, package checkout path, `--package-path`, or environment variable is needed. The Xcode Command Plugin receives the current project directory directly.

### Commit or ignore the output

`Docs/BackendAPIReference` is ordinary project output. Commit it when it is a reviewed team reference, or add the directory to `.gitignore` when it is only a local artifact. In either case, keep it out of the App bundle.

## Automatic preview: `BackendReferencePlugin`

Use the Build Tool Plugin when the document should be refreshed on every build but does not need to be saved in the repository.

### Configure it on an App target

1. In Xcode, select the App project in the navigator.
2. Select the **App target**, then open **Build Phases**.
3. Expand **Run Build Tool Plug-ins**.
4. Click `+`, select **BackendReferencePlugin (NetworkingKit)**, then add it.
5. Build the App. If Xcode asks to trust the plugin after a package update, review it and choose **Trust & Enable**.
6. Open the **Report navigator** (⌘9), select the build, and expand **Generate backend API reference**. Its `BackendAPIReference/index.html` output is in that target's plugin work directory under Xcode Derived Data.

SwiftPM Build Tool Plugins are sandboxed. They cannot write to `$SRCROOT`, so this plugin cannot create `Docs/BackendAPIReference` in the App project. That is expected behaviour, not a configuration error. Use the Command Plugin for a fixed project-root document.

## Recognition rules

The generator uses static source analysis. The following shape gives the most useful reference:

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

- A `NetworkClient` or `SharedNetworkClient` `baseURL` identifies one server.
- A request protocol constrained to one concrete client associates request types with that server.
- `RestfulRequest` and `GraphQLRequest` declarations become endpoints. GraphQL endpoints use `/graphql` and `POST`; their `query`, `variables`, and `operationName` declarations are shown as request parameters when statically available.
- The closest preceding `// MARK: - Feature name` groups the endpoints.
- Stored request properties become parameters. The client `configuration` becomes the Configuration table.

The scanner does not execute Swift. Dynamic URLs, HTTP methods, or complex expressions remain source expressions where possible, or appear as `<dynamic>`. Computed values cannot always be resolved to their final runtime value.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| The command is missing from **File → Packages** | Resolve package versions, confirm that the project depends on NetworkingKit 2.4.3 or later, then reopen the project. |
| Xcode says the plugin is disabled or untrusted | Run the command/build again and choose **Trust & Enable** or **Allow Command to Change Files** in the Xcode prompt. |
| The Build Tool Plugin does not create a `Docs` directory | Expected: its sandbox only permits Derived Data output. Run `BackendReferenceCommandPlugin` instead. |
| A request or Feature is absent | Check the concrete-client protocol constraint, `RestfulRequest`/`GraphQLRequest` conformance, and that the `// MARK:` line precedes the request declaration. |
| Values show as `<dynamic>` | Use a literal or statically resolvable value when possible; runtime code is intentionally not executed. |

For non-Xcode automation, invoke `BackendReferenceGenerator` from a checked-out package with `--source-directory`, `--output-directory`, and `--stamp`. This is a fallback for CI; the Command Plugin is the normal Xcode workflow.
