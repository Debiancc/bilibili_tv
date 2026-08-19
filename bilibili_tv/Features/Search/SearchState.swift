import Foundation

/// 搜索页状态：互斥业务态，禁止布尔/Optional 拼接
enum SearchState: Equatable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}
