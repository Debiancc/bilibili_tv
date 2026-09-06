import SwiftUI

enum DetailDesign {
    enum Typography {
        static let episodeNumber: CGFloat = 25
        static let body: CGFloat = 29
        static let previewTitle: CGFloat = 48
    }

    enum UpNext {
        static let cardWidth: CGFloat = 320
        static let artworkHeight: CGFloat = 180
        static let cardSpacing: CGFloat = 30
        static let horizontalInset: CGFloat = 90
    }

    enum Picker {
        static let horizontalInset: CGFloat = 120
        static let rangeWidth: CGFloat = 180
        static let rangeHeight: CGFloat = 60
        static let gridMinimumWidth: CGFloat = 140
        static let gridTileHeight: CGFloat = 80
        static let gridSpacing: CGFloat = 20
        static let previewWidth: CGFloat = 680
        static let previewArtworkHeight: CGFloat = 380
        static let cornerRadius: CGFloat = 16
        static let focusTint = Color(red: 1.0, green: 0.38, blue: 0.56)
        static let unfocusedFill = Color.white.opacity(0.10)
        static let focusedFill = Color.white.opacity(0.18)
        static let unfocusedStroke = Color.white.opacity(0.06)
    }
}
