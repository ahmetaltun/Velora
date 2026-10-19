import Foundation

public enum ViewMode: String, CaseIterable, Identifiable {
    case sunburst = "Sunburst"
    case table = "Table"
    case columns = "Columns"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .sunburst: return "circle.dashed"
        case .table: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
}
