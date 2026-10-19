import Foundation

public enum ViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case sunburst = "Sunburst"
    case columns = "Columns"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .table: return "list.bullet"
        case .sunburst: return "circle.dashed"
        case .columns: return "rectangle.split.3x1"
        }
    }
}
