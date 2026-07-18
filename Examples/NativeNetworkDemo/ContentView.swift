import SwiftUI

struct ContentView: View {
    @StateObject private var model = DemoViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "network")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                Group {
                    if let todo = model.todo {
                        VStack(spacing: 6) {
                            Text("REST Todo #\(todo.id)").font(.headline)
                            Text(todo.title).multilineTextAlignment(.center)
                            Label(todo.completed ? "Completed" : "Open", systemImage: todo.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(todo.completed ? .green : .secondary)
                        }
                    } else if let character = model.character {
                        VStack(spacing: 6) {
                            Text("GraphQL Character").font(.headline)
                            Text(character.name).font(.title3.bold())
                            Text(character.species).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(model.message).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)

                HStack {
                    Button("Load REST") { model.loadTodo() }
                        .buttonStyle(.borderedProminent)
                    Button("Load GraphQL") { model.loadCharacter() }
                        .buttonStyle(.bordered)
                }

                if model.isLoading { ProgressView() }

                Text("NativeNetwork on \(platformName)\nAsync/Await · REST · GraphQL · Retry · Redacted Logging")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("NativeNetwork Demo")
        }
    }

    private var platformName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }
}

#Preview { ContentView() }
