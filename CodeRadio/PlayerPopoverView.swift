import AppKit
import SwiftUI

struct PlayerPopoverView: View {
    @Bindable var player: CodeRadioPlayer
    @Bindable var launchAtLogin: LaunchAtLoginController

    @State private var isHistoryExpanded = false

    private let popoverWidth: CGFloat = 320
    private let artworkSize: CGFloat = 156

    var body: some View {
        VStack(spacing: 0) {
            playerContent
            recentSongsSection
        }
        .frame(width: popoverWidth)
        .background(.regularMaterial)
        .overlay(alignment: .topTrailing) {
            settingsMenu
                .padding(14)
        }
        .onAppear {
            launchAtLogin.refresh()
        }
    }

    private var playerContent: some View {
        VStack(spacing: 0) {
            artwork
                .padding(.top, 28)

            songDetails
                .padding(.top, 16)

            progressSection
                .padding(.top, 12)

            controlsSection
                .padding(.top, 14)

            if let statusMessage {
                statusBanner(statusMessage)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    private var artwork: some View {
        artworkImage
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 9)
            .overlay(alignment: .bottom) {
                liveBadge
                    .offset(y: 12)
            }
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current song artwork")
    }

    @ViewBuilder
    private var artworkImage: some View {
        if let artURL = player.currentSong?.art {
            AsyncImage(url: artURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.47, blue: 0.52),
                    Color(red: 0.48, green: 0.39, blue: 0.95),
                    Color(red: 0.26, green: 0.69, blue: 0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.yellow.opacity(0.75))
                .frame(width: 94, height: 94)
                .offset(x: -60, y: 62)

            Circle()
                .fill(Color(red: 0.08, green: 0.16, blue: 0.29).opacity(0.86))
                .frame(width: 66, height: 66)
                .offset(x: 18, y: -22)

            Image(systemName: "radio.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipped()
    }

    @ViewBuilder
    private var liveBadge: some View {
        let label = HStack(spacing: 5) {
            Circle()
                .fill(player.isOnline ? .green : .red)
                .frame(width: 6, height: 6)

            Text(liveBadgeText)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 24)

        if #available(macOS 26.0, *) {
            label
                .glassEffect(.regular, in: .capsule)
        } else {
            label
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                }
        }
    }

    private var liveBadgeText: String {
        guard player.isOnline else { return "Offline" }
        guard player.listenerCount > 0 else { return "Live" }
        return "Live · \(player.listenerCount.formatted())"
    }

    private var songDetails: some View {
        VStack(spacing: 4) {
            Text(player.currentSong?.title ?? "Code Radio")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(player.currentSong?.artist ?? "Music designed for coding")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var progressSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = elapsedTime(at: context.date)
            let remaining = max(player.songDuration - elapsed, 0)

            VStack(spacing: 5) {
                ProgressView(value: progress(at: context.date))
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .accessibilityLabel("Song progress")

                HStack {
                    Text(timeLabel(elapsed))
                    Spacer()
                    Text("−\(timeLabel(remaining))")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            }
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 8) {
            controlsIsland

            Text("Volume \(Int((player.volume * 100).rounded()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var controlsIsland: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                controls
                    .padding(6)
                    .glassEffect(
                        .regular.tint(.accentColor.opacity(0.10)).interactive(),
                        in: .capsule
                    )
            }
        } else {
            controls
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            volumeButton(
                systemImage: "minus",
                label: "Decrease volume",
                adjustment: -0.1
            )

            Button {
                player.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(.primary)

                    Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .offset(x: player.isPlaying ? 0 : 1)
                }
                .frame(width: 48, height: 48)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .help(player.isPlaying ? "Stop" : "Play")
            .accessibilityLabel(player.isPlaying ? "Stop Code Radio" : "Play Code Radio")

            volumeButton(
                systemImage: "plus",
                label: "Increase volume",
                adjustment: 0.1
            )
        }
    }

    private func volumeButton(
        systemImage: String,
        label: String,
        adjustment: Double
    ) -> some View {
        Button {
            player.volume += adjustment
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((player.volume * 100).rounded())) percent")
    }

    private var recentSongsSection: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                withAnimation(.snappy(duration: 0.24)) {
                    isHistoryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isHistoryExpanded ? 90 : 0))

                    Text("Recently played")
                        .font(.caption.weight(.medium))

                    Spacer()

                    Text("\(visibleHistory.count) tracks")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .accessibilityLabel("Recently played, \(visibleHistory.count) tracks")
            .accessibilityValue(isHistoryExpanded ? "Expanded" : "Collapsed")

            if isHistoryExpanded {
                VStack(spacing: 0) {
                    ForEach(visibleHistory) { song in
                        historyRow(song)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var visibleHistory: [Song] {
        Array(player.songHistory.prefix(3))
    }

    private func historyRow(_ song: Song) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.caption)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 42)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Menu {
            Picker("Stream Quality", selection: $player.selectedQuality) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.label).tag(quality)
                }
            }

            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                .disabled(!launchAtLogin.isAvailable)

            if launchAtLogin.requiresApproval {
                Button("Approve in System Settings…") {
                    launchAtLogin.openSystemSettings()
                }
            }

            Divider()

            Button("Refresh Now Playing") {
                Task { await player.refreshMetadata() }
            }
            .disabled(player.isRefreshing)

            Button("Open Code Radio Website") {
                player.openWebsite()
            }

            Divider()

            Button("Quit Code Radio") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            settingsMenuLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Code Radio options")
        .accessibilityLabel("Code Radio options")
    }

    @ViewBuilder
    private var settingsMenuLabel: some View {
        let label = Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 30, height: 30)
            .contentShape(.circle)

        if #available(macOS 26.0, *) {
            label
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            label
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isRequested },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var statusMessage: StatusMessage? {
        if let error = player.errorMessage {
            return StatusMessage(text: error, color: .orange)
        }
        if let error = launchAtLogin.errorMessage {
            return StatusMessage(text: error, color: .red)
        }
        if launchAtLogin.requiresApproval {
            return StatusMessage(
                text: "Approve Launch at Login in System Settings",
                color: .orange
            )
        }
        return nil
    }

    private func statusBanner(_ message: StatusMessage) -> some View {
        Label(message.text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(message.color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(message.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    private func elapsedTime(at date: Date) -> TimeInterval {
        guard let playedAt = player.playedAt, player.songDuration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(playedAt), 0), player.songDuration)
    }

    private func progress(at date: Date) -> Double {
        guard player.songDuration > 0 else { return 0 }
        return elapsedTime(at: date) / player.songDuration
    }

    private func timeLabel(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct StatusMessage {
    let text: String
    let color: Color
}

#Preview {
    PlayerPopoverView(
        player: CodeRadioPlayer(),
        launchAtLogin: LaunchAtLoginController()
    )
}
