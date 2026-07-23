# Backend API HTML reference

NetworkingKit can scan an Xcode app's Swift source and create a browsable HTML reference of backend servers, configuration values, feature-grouped endpoints, parameters, requests, and source files.

## Recommended: generate files in `Docs`

Use `BackendReferenceCommandPlugin` when the reference should live in the app project and be easy to open, commit, or attach to an artifact.

The plugin writes its entry page to:

```text
$SRCROOT/Docs/BackendAPIReference/index.html
```

### Xcode steps

1. Add `NetworkingKit` through **File → Add Package Dependencies…**.
2. Select **File → Packages → Generate Backend API Reference**.
3. On first use, inspect the plugin and choose **Allow Command to Change Files**. This grants permission to write inside the project `Docs/` directory.
4. Open `Docs/BackendAPIReference/index.html` in Finder or a browser.
5. Run the same menu command whenever the app's networking definitions change.

No Run Script, checkout path, or environment variable is required. The Xcode command plugin receives the current project directory directly.

## Build-time preview

`BackendReferencePlugin` is a Build Tool Plugin for automatically generating the same reference during every build:

1. Select the App target and open **Build Phases**.
2. In **Run Build Tool Plug-ins**, click `+` and choose `BackendReferencePlugin`.
3. Build the app.
4. Open the plugin output in the Xcode Report navigator; its entry page is `BackendAPIReference/index.html` in Derived Data.

Build Tool Plugins are sandboxed and cannot write into the project root. Use the Command Plugin when the HTML must be saved in `Docs/`.

## Discovery rules

- A `NetworkClient` or `SharedNetworkClient` `baseURL` identifies a backend server.
- An app request protocol constrained to a concrete client associates requests with that server.
- `RestfulRequest` and `GraphQLRequest` declarations are endpoints.
- The nearest preceding `// MARK: - Feature name` groups endpoints into features.
- Stored request properties are parameters; configuration values are displayed in a configuration table.

The scanner does not execute Swift code. Dynamic expressions remain source expressions or are shown as `<dynamic>`.
