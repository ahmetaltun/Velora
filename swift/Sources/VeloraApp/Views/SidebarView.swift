import SwiftUI

public struct SidebarView: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        List {
            Section("Volumes") {
                Button(action: {
                    viewModel.navigateToRoot()
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .foregroundColor(viewModel.activeSidebarId == "volume_root" ? .accentColor : .blue)
                            Text("Macintosh HD")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundColor(viewModel.activeSidebarId == "volume_root" ? .accentColor : .primary)
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
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        viewModel.activeSidebarId == "volume_root" ? Color.accentColor.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Section("Favorites") {
                SidebarRowItem(
                    title: "Home",
                    systemImage: "house.fill",
                    isSelected: viewModel.activeSidebarId == "fav_home"
                ) {
                    viewModel.navigateToFavorite(
                        id: "fav_home",
                        path: FileManager.default.homeDirectoryForCurrentUser.path
                    )
                }

                SidebarRowItem(
                    title: "Developer",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isSelected: viewModel.activeSidebarId == "fav_dev"
                ) {
                    let devPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Rust")
                    viewModel.navigateToFavorite(
                        id: "fav_dev",
                        path: devPath
                    )
                }

                SidebarRowItem(
                    title: "Downloads",
                    systemImage: "arrow.down.circle.fill",
                    isSelected: viewModel.activeSidebarId == "fav_downloads"
                ) {
                    let dlPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
                    viewModel.navigateToFavorite(
                        id: "fav_downloads",
                        path: dlPath
                    )
                }
            }

            Section("Smart Filters") {
                SidebarRowItem(
                    title: "Large Files (>100MB)",
                    systemImage: "shippingbox.fill",
                    isSelected: viewModel.activeSidebarId == "filter_large"
                ) {
                    viewModel.activeSidebarId = "filter_large"
                    viewModel.performSearch(query: "size:>100mb")
                    viewModel.selectedViewMode = .table
                }

                SidebarRowItem(
                    title: "Developer Caches",
                    systemImage: "hammer.fill",
                    isSelected: viewModel.activeSidebarId == "filter_dev_caches"
                ) {
                    viewModel.activeSidebarId = "filter_dev_caches"
                    viewModel.performSearch(query: "target | node_modules | deriveddata")
                    viewModel.selectedViewMode = .table
                }

                SidebarRowItem(
                    title: "Modified Today",
                    systemImage: "clock.fill",
                    isSelected: viewModel.activeSidebarId == "filter_today"
                ) {
                    viewModel.activeSidebarId = "filter_today"
                    viewModel.performSearch(query: "dm:today")
                    viewModel.selectedViewMode = .table
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRowItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(.body, design: .rounded, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
