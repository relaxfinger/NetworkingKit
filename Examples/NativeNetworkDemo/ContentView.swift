import SwiftUI

struct ContentView: View {
    @StateObject private var model = DemoViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: DemoLayout.verticalSpacing) {
                Image(systemName: "network")
                    .font(.system(size: DemoLayout.iconSize))
                    .foregroundStyle(.tint)

                Group {
                    if let character = model.restCharacter {
                        VStack(spacing: DemoLayout.resultSpacing) {
                            Text("REST Character #\(character.id)").font(.headline)
                            Text(character.name).font(.title3.bold())
                            Text("\(character.species) · \(character.status)").foregroundStyle(.secondary)
                        }
                    } else if let character = model.graphQLCharacter {
                        VStack(spacing: DemoLayout.resultSpacing) {
                            Text("GraphQL Character").font(.headline)
                            Text(character.name).font(.title3.bold())
                            Text("\(character.species) · \(character.status)").foregroundStyle(.secondary)
                        }
                    } else {
                        Text(model.message).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: DemoLayout.maximumContentWidth)
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

private enum DemoLayout {
    static let iconSize: CGFloat = 52
    static let verticalSpacing: CGFloat = 20
    static let resultSpacing: CGFloat = 6
    static let maximumContentWidth: CGFloat = 420
}

#Preview { ContentView() }
