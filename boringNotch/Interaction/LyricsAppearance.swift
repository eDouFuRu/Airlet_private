import Defaults
import SwiftUI

/// One live style for lyrics in both the compact row and the expanded player.
struct LyricsAppearance: DynamicProperty {
    @Environment(\.islandAppearance) private var islandAppearance
    @Default(.lyricsColorMode) private var mode
    @Default(.customLyricsColor) private var customColor
    @ObservedObject private var music = MusicManager.shared

    var color: Color { color(in: islandAppearance) }

    func color(in appearance: IslandAppearance) -> Color {
        switch mode {
        case .white:
            return appearance.primary
        case .custom:
            return customColor
        case .albumArt:
            guard !music.usingAppIconForArtwork else { return appearance.primary }
            return appearance.artworkTint(Color(nsColor: music.avgColor))
        }
    }
}
