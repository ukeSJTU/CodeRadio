import AppKit
import SwiftUI

struct PlayerPopoverView: View {
    @Bindable var player: CodeRadioPlayer

    var body: some View {
        VStack(spacing: 0) {
            nowPlayingSection
            Divider()
            controlsSection
            Divider()
            recentSongsSection
            Divider()
            footer
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private var nowPlayingSection: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(player.isOnline ? .green : .red)
                        .frame(width: 7, height: 7)
                    Text(player.isOnline ? "LIVE" : "OFFLINE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    if player.listenerCount > 0 {
                        Text("• \(player.listenerCount) listeners")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(player.currentSong?.title ?? "Code Radio")
                    .font(.headline)
                    .lineLimit(2)

                Text(player.currentSong?.artist ?? "24/7 music designed for coding")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let album = player.currentSong?.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ProgressView(value: player.progress)
                        .progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artURL = player.currentSong?.art {
            AsyncImage(url: artURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    artworkPlaceholder
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(.rect(cornerRadius: 10))
        } else {
            artworkPlaceholder
                .frame(width: 76, height: 76)
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
            Image(systemName: "radio.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .help(player.isPlaying ? "Stop" : "Play")

                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)

                Slider(value: $player.volume, in: 0...1)
                    .accessibilityLabel("Volume")
            }

            Picker("Stream quality", selection: $player.selectedQuality) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let errorMessage = player.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var recentSongsSection: some View {
        if !player.songHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recently played")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(player.songHistory.prefix(4).enumerated()), id: \.offset) { _, song in
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(song.title)
                                .font(.caption)
                                .lineLimit(1)
                            Text(song.artist)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open website") {
                player.openWebsite()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if player.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await player.refreshMetadata() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh metadata")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

#Preview {
    PlayerPopoverView(player: CodeRadioPlayer())
}
