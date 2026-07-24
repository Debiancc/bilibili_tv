import Foundation
import SwiftUI
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var currentCursor: Int = 0
    private var hasNext: Bool = true
    
    func fetchInitialFeed() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let data = try await BilibiliService.shared.fetchMovieFeed(cursor: 0)
            self.items = data.items
            self.currentCursor = data.coursor
            self.hasNext = data.hasNext
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func fetchNextPage() async {
        guard !isLoading && hasNext else { return }
        isLoading = true
        
        do {
            let data = try await BilibiliService.shared.fetchMovieFeed(cursor: currentCursor)
            self.items.append(contentsOf: data.items)
            self.currentCursor = data.coursor
            self.hasNext = data.hasNext
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
