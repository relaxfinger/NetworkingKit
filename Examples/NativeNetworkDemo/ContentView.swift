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
                    if let character = model.restCharacter {
                        VStack(spacing: 6) {
                            Text("REST Character #\(character.id)").font(.headline)
                            Text(character.name).font(.title3.bold())
                            Text("\(character.species) · \(character.status)").foregroundStyle(.secondary)
                        }
                    } else if let character = model.graphQLCharacter {
                        VStack(spacing: 6) {
                            Text("GraphQL Character").font(.headline)
                            Text(character.name).font(.title3.bold())
                            Text("\(character.species) · \(character.status)").foregroundStyle(.secondary)
                        }
                    } else {
                        Text(model.message).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)

                HStack {
                    Button("Load REST") { model.loadRESTCharacter() }
                        .buttonStyle(.borderedProminent)
                    Button("Load GraphQL") { model.loadGraphQLCharacter() }
                        .buttonStyle(.bordered)
                }

                if model.isLoading { ProgressView() }

                Text("NativeNetwork on \(platformName)\nAppNetworkClient · AppRequest · REST · GraphQL")
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
