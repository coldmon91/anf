import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case icons, list, columns, gallery
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .icons:   return "square.grid.2x2"
        case .list:    return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        case .gallery: return "square.stack"
        }
    }

    var title: String {
        switch self {
        case .icons:   return "아이콘"
        case .list:    return "리스트"
        case .columns: return "컬럼"
        case .gallery: return "갤러리"
        }
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, dateModified, size, kind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "이름"
        case .dateModified: return "수정일"
        case .size: return "크기"
        case .kind: return "종류"
        }
    }
}

struct SortOrder: Equatable {
    var key: SortKey = .name
    var ascending: Bool = true
}
