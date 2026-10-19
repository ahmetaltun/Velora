import SwiftUI

public struct SidebarView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section("Volumes") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "internaldrive.fill")
                            .foregroundColor(.blue)
                        Text("Macintosh HD")
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Spacer()
                        Text("68%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Disk Gauge Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                            Capsule()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * 0.68)
                        }
                    }
                    .frame(height: 6)

                    Text("340 GB of 500 GB free")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                HStack {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading) {
                        Text("Samsung T7")
                        Text("Unplugged (Cataloged)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .opacity(0.6)
            }

            Section("Favorites") {
                NavigationLink(destination: EmptyView()) {
                    Label("Home", systemImage: "house.fill")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.currentPath = FileManager.default.homeDirectoryForCurrentUser.path
                    viewModel.scanCurrentPath()
                })

                NavigationLink(destination: EmptyView()) {
                    Label("Developer", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    let devPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Rust")
                    viewModel.currentPath = devPath
                    viewModel.scanCurrentPath()
                })

                NavigationLink(destination: EmptyView()) {
                    Label("Downloads", systemImage: "arrow.down.circle.fill")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    let dlPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
                    viewModel.currentPath = dlPath
                    viewModel.scanCurrentPath()
                })
            }

            Section("Smart Filters") {
                Button(action: {
                    viewModel.performSearch(query: "size:>500mb")
                    viewModel.selectedViewMode = .table
                }) {
                    Label("Large Files (>500MB)", systemImage: "shippingbox.fill")
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.performSearch(query: "target | node_modules | deriveddata")
                    viewModel.selectedViewMode = .table
                }) {
                    Label("Developer Caches", systemImage: "hammer.fill")
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.performSearch(query: "dm:today")
                    viewModel.selectedViewMode = .table
                }) {
                    Label("Modified Today", systemImage: "clock.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
    }
}
