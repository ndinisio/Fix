import SwiftUI

/// A video result. Tapping opens it in YouTube or Safari — FIX does not wrap
/// someone else's player in an in-app browser.
struct VideoRow: View {
    let video: VideoResult

    /// Scales with the text size so the row stays balanced at large Dynamic
    /// Type settings instead of leaving a tiny image beside huge text.
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth: CGFloat = 104

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(video.channelName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let duration = video.duration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the video outside FIX")
    }

    private var thumbnail: some View {
        AsyncImage(url: video.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                // Failed and missing thumbnails look the same on purpose: a
                // placeholder is honest, an invented image would not be.
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        var parts = [video.title, video.channelName]
        if let duration = video.duration { parts.append(duration) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    List {
        VideoRow(video: VideoResult(
            id: "1",
            title: "MacBook Air not charging — five things to check first",
            channelName: "Repair Workshop",
            thumbnailURL: nil,
            videoURL: URL(string: "https://www.youtube.com")!,
            duration: "8:41"
        ))
    }
}
