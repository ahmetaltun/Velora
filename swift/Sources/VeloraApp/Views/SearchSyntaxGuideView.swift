import SwiftUI
import VeloraCore

/// Inline query syntax hint chips and cheat sheet popover for informing the user of special search filters.
public struct SearchSyntaxChipsView: View {
    @Bindable public var viewModel: VeloraViewModel
    @State private var showCheatSheet: Bool = false

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private let sampleChips: [(label: String, token: String, help: String)] = [
        ("size:>100MB", "size:>100MB", "Filter files larger than 100MB (>100MB, <1GB, etc.)"),
        ("ext:rs", "ext:rs", "Filter by file extension (e.g. ext:rs, ext:swift,dmg)"),
        ("type:dir", "type:dir", "Match folders only (or type:file)"),
        ("dm:today", "dm:today", "Modified today (also dm:pastweek, dm:pastmonth)"),
        ("!target", "!target", "Exclude files matching keyword")
    ]

    public var body: some View {
        HStack(spacing: 6) {
            Text("Filters:")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(VeloraTheme.textMuted)

            ForEach(sampleChips, id: \.token) { chip in
                let isActive = isTokenActive(chip.token)
                Button(action: {
                    toggleQueryToken(chip.token)
                }) {
                    Text(chip.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isActive ? VeloraTheme.obsidianBase : VeloraTheme.accentCyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            isActive ? VeloraTheme.accentCyan : VeloraTheme.obsidianSurface,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(isActive ? VeloraTheme.accentCyan : VeloraTheme.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(chip.help)
            }

            // Interactive Cheatsheet Guide Popover
            Button(action: {
                showCheatSheet.toggle()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Syntax")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundColor(showCheatSheet ? VeloraTheme.accentViolet : VeloraTheme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(VeloraTheme.obsidianSurface, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(showCheatSheet ? VeloraTheme.accentViolet : VeloraTheme.cardBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Click to view full special search query cheat sheet")
            .popover(isPresented: $showCheatSheet, arrowEdge: .bottom) {
                SearchSyntaxGuidePopover(viewModel: viewModel)
            }
        }
    }

    private func isTokenActive(_ token: String) -> Bool {
        viewModel.searchQuery.contains(token)
    }

    private func toggleQueryToken(_ token: String) {
        var query = viewModel.searchQuery.trimmingCharacters(in: .whitespaces)
        if query.contains(token) {
            query = query.replacingOccurrences(of: token, with: "").trimmingCharacters(in: .whitespaces)
            while query.contains("  ") {
                query = query.replacingOccurrences(of: "  ", with: " ")
            }
        } else {
            if let colonIndex = token.firstIndex(of: ":") {
                let prefix = String(token[...colonIndex])
                let parts = query.components(separatedBy: " ")
                let filtered = parts.filter { !$0.starts(with: prefix) }
                query = (filtered + [token]).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            } else {
                query = query.isEmpty ? token : "\(query) \(token)"
            }
        }
        viewModel.searchQuery = query
        viewModel.performSearch(query: query, debounce: false)
    }
}

/// Detailed cheatsheet popover showing all supported query modifiers.
public struct SearchSyntaxGuidePopover: View {
    @Bindable public var viewModel: VeloraViewModel

    public init(viewModel: VeloraViewModel) {
        self.viewModel = viewModel
    }

    private struct QuerySyntaxItem: Identifiable {
        let id = UUID()
        let syntax: String
        let example: String
        let description: String
        let color: Color
    }

    private let items: [QuerySyntaxItem] = [
        QuerySyntaxItem(
            syntax: "size:<op><val>",
            example: "size:>100MB",
            description: "Filter by file size (>, >=, <, <=, =). Units: B, KB, MB, GB",
            color: VeloraTheme.accentAmber
        ),
        QuerySyntaxItem(
            syntax: "ext:<extension>",
            example: "ext:rs,swift",
            description: "Match specific file extensions, comma-separated",
            color: VeloraTheme.accentCyan
        ),
        QuerySyntaxItem(
            syntax: "dm:<timeframe>",
            example: "dm:today",
            description: "Modified date: today, yesterday, pastweek, pastmonth, pastyear",
            color: VeloraTheme.accentEmerald
        ),
        QuerySyntaxItem(
            syntax: "type:<kind>",
            example: "type:dir",
            description: "Filter directories only (type:dir) or files only (type:file)",
            color: VeloraTheme.accentViolet
        ),
        QuerySyntaxItem(
            syntax: "!<exclude_term>",
            example: "!target",
            description: "Exclude files or paths containing this term",
            color: VeloraTheme.accentPink
        ),
        QuerySyntaxItem(
            syntax: "<term1> | <term2>",
            example: "swift | rust",
            description: "Boolean OR: matches either term across names and paths",
            color: VeloraTheme.accentBlue
        ),
        QuerySyntaxItem(
            syntax: "path:<prefix>",
            example: "path:Documents",
            description: "Restrict search to items within a specific directory path",
            color: VeloraTheme.textSecondary
        )
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(VeloraTheme.accentCyan)
                Text("Special Search Queries")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(VeloraTheme.textPrimary)

                Spacer()

                Text("Sub-millisecond RAM Engine")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(VeloraTheme.accentEmerald)
            }

            Text("Combine keywords with power filters to narrow down millions of files instantly. Click any pill to try it:")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(VeloraTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(VeloraTheme.cardBorder)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Button(action: {
                            applyExample(item.example)
                        }) {
                            Text(item.example)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(item.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(item.color.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Click to insert '\(item.example)' into search")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.syntax)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(VeloraTheme.textPrimary)
                            Text(item.description)
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundColor(VeloraTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(VeloraTheme.obsidianElevated)
        .preferredColorScheme(.dark)
    }

    private func applyExample(_ example: String) {
        var query = viewModel.searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.contains(example) {
            query = query.isEmpty ? example : "\(query) \(example)"
            viewModel.searchQuery = query
            viewModel.performSearch(query: query, debounce: false)
        }
    }
}
