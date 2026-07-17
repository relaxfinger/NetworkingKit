# Contributing

Thanks for contributing. Please open an issue before substantial changes so the API stays small and consistent.

1. Create a focused branch from `main`.
2. Add or update tests for observable behavior.
3. Run `swift test` locally.
4. Update the README when public API usage changes.
5. Open a pull request using the provided template.

Public APIs should be clear at the call site, documented with `///`, `Sendable` where appropriate, and compatible with Swift 6 strict concurrency.
