import Combine
import NetworkingKit
import SwiftUI

struct ContentView: View {
    @State private var user: DemoUser?
    @State private var message = "点击按钮开始请求"
    @State private var isLoading = false
    @State private var subscriptions = Set<AnyCancellable>()

    private let api = APIClient(baseURL: URL(string: "https://jsonplaceholder.typicode.com")!)

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "network")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)

                Group {
                    if let user {
                        VStack(spacing: 6) {
                            Text(user.name).font(.title2.bold())
                            Text(user.email).foregroundStyle(.secondary)
                            Text("@\(user.username)").foregroundStyle(.secondary)
                        }
                    } else {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)

                Button("Async/Await 获取用户") { loadWithConcurrency() }
                    .buttonStyle(.borderedProminent)

                Button("Combine 获取用户") { loadWithCombine() }
                    .buttonStyle(.bordered)

                if isLoading { ProgressView() }

                Text("REST: api.send(.get(\"users/1\"))\nGraphQL 示例见 DemoGraphQL.swift")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)
            }
            .padding()
            .navigationTitle("NetworkingKit Demo")
        }
    }

    private func loadWithConcurrency() {
        Task {
            await setLoading(true)
            do {
                let response: DemoUser = try await api.send(.get("users/1"))
                await show(response)
            } catch {
                await show(error)
            }
        }
    }

    private func loadWithCombine() {
        isLoading = true
        api.publisher(.get("users/1"), as: DemoUser.self)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case let .failure(error) = completion { message = "请求失败：\(error)" }
                    isLoading = false
                },
                receiveValue: { user in self.user = user }
            )
            .store(in: &subscriptions)
    }

    @MainActor private func setLoading(_ value: Bool) { isLoading = value; if value { message = "正在加载…" } }
    @MainActor private func show(_ response: DemoUser) { user = response; isLoading = false }
    @MainActor private func show(_ error: Error) { message = "请求失败：\(error.localizedDescription)"; isLoading = false }
}

struct DemoUser: Codable, Sendable {
    let name: String
    let username: String
    let email: String
}

#Preview { ContentView() }
