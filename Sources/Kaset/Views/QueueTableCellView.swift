import AppKit
import SwiftUI

// MARK: - QueueCellActions

@available(macOS 26.0, *)
struct QueueCellActions {
    let onPlay: () -> Void
    let onRemove: () -> Void
    /// Optional: invoked when the title text is clicked, if the song's album
    /// is navigable.
    var onNavigateAlbum: (() -> Void)?
    /// Optional: invoked when the artist text is clicked, if the song's
    /// primary artist is navigable.
    var onNavigateArtist: (() -> Void)?
}

// MARK: - QueueTableCellView

@available(macOS 26.0, *)
class QueueTableCellView: NSView {
    private var onPlay: (() -> Void)?
    private var onRemove: (() -> Void)?
    private var onNavigateAlbum: (() -> Void)?
    private var onNavigateArtist: (() -> Void)?
    private var isCurrentTrack: Bool = false
    private var isPlaying: Bool = false
    private var indicatorLabel = NSTextField()
    private var waveformView: NSView?
    private let thumbnailImageView = NSImageView()
    private var imageLoadTask: Task<Void, Never>?
    private var currentSongId: String?
    private let titleLabel = NavigableLabel()
    private let artistLabel = NavigableLabel()
    private let durationLabel = NSTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupView()
    }

    private func setupView() {
        wantsLayer = true
        // Fill the row view so layout is consistent when the table reuses row views (fixes misaligned rows).
        autoresizingMask = [.width, .height]

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.alignment = .centerY
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 8) // Reduced right padding
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Indicator container (for number or waveform) — keep fixed so long text doesn't shift row layout
        let indicatorContainer = NSView()
        indicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        let indicatorWidth = indicatorContainer.widthAnchor.constraint(equalToConstant: 24)
        indicatorWidth.priority = .required
        indicatorWidth.isActive = true
        indicatorContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true
        indicatorContainer.setContentHuggingPriority(.required, for: .horizontal)
        indicatorContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        self.indicatorLabel.isEditable = false
        self.indicatorLabel.isBordered = false
        self.indicatorLabel.backgroundColor = .clear
        self.indicatorLabel.alignment = .center
        self.indicatorLabel.font = NSFont.systemFont(ofSize: 12)
        self.indicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        indicatorContainer.addSubview(self.indicatorLabel)
        NSLayoutConstraint.activate([
            self.indicatorLabel.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
            self.indicatorLabel.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor),
        ])

        self.thumbnailImageView.wantsLayer = true
        self.thumbnailImageView.layer?.cornerRadius = 4
        self.thumbnailImageView.layer?.masksToBounds = true
        self.thumbnailImageView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        self.thumbnailImageView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        self.thumbnailImageView.setContentHuggingPriority(.required, for: .horizontal)
        self.thumbnailImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let infoStackView = NSStackView()
        infoStackView.orientation = .vertical
        infoStackView.spacing = 2
        infoStackView.alignment = .leading

        self.titleLabel.isEditable = false
        self.titleLabel.isBordered = false
        self.titleLabel.backgroundColor = .clear
        self.titleLabel.lineBreakMode = .byTruncatingTail

        self.artistLabel.isEditable = false
        self.artistLabel.isBordered = false
        self.artistLabel.backgroundColor = .clear
        self.artistLabel.lineBreakMode = .byTruncatingTail
        self.artistLabel.font = NSFont.systemFont(ofSize: 11)
        self.artistLabel.textColor = NSColor.secondaryLabelColor

        // Hide the child text fields from the accessibility tree so VoiceOver
        // reads the row's composed label (see configureAccessibility) rather
        // than fragmented fields. See P2F019.
        self.titleLabel.setAccessibilityElement(false)
        self.artistLabel.setAccessibilityElement(false)

        infoStackView.addArrangedSubview(self.titleLabel)
        infoStackView.addArrangedSubview(self.artistLabel)

        self.durationLabel.isEditable = false
        self.durationLabel.isBordered = false
        self.durationLabel.backgroundColor = .clear
        self.durationLabel.alignment = .right
        self.durationLabel.font = NSFont.systemFont(ofSize: 11)
        self.durationLabel.textColor = NSColor.tertiaryLabelColor
        self.durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal) // Don't compress duration
        self.durationLabel.setAccessibilityElement(false)
        self.indicatorLabel.setAccessibilityElement(false)
        self.thumbnailImageView.setAccessibilityElement(false)

        // Spacer takes all flexible space so title/artist and duration stay consistently aligned across rows
        let spacerView = NSView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        spacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        infoStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // Truncate before spacer grows

        stackView.addArrangedSubview(indicatorContainer)
        stackView.addArrangedSubview(self.thumbnailImageView)
        stackView.addArrangedSubview(infoStackView)
        stackView.addArrangedSubview(spacerView)
        stackView.addArrangedSubview(self.durationLabel)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(clickGesture)

        // Per-label clicks for title→album / artist→artist navigation.
        // The labels intercept clicks and stop propagation when their
        // navigation closure is set, so the row's play handler doesn't fire.
        self.titleLabel.onClick = { [weak self] in self?.handleTitleClick() }
        self.artistLabel.onClick = { [weak self] in self?.handleArtistClick() }
    }

    override func layout() {
        super.layout()
        // Ensure we always fill the row view so reused rows don't keep a stale frame (fixes misaligned rows).
        if let sv = superview, !sv.bounds.isEmpty, frame != sv.bounds {
            frame = sv.bounds
        }
    }

    func configure(song: Song, index: Int, isCurrentTrack: Bool, isPlaying: Bool, actions: QueueCellActions) {
        self.onPlay = actions.onPlay
        self.onRemove = actions.onRemove
        self.onNavigateAlbum = actions.onNavigateAlbum
        self.onNavigateArtist = actions.onNavigateArtist
        self.titleLabel.isClickable = actions.onNavigateAlbum != nil
        self.artistLabel.isClickable = actions.onNavigateArtist != nil
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isPlaying
        self.updateAppearance(isCurrentTrack: isCurrentTrack, isPlaying: isPlaying, index: index)

        self.titleLabel.stringValue = song.title
        self.titleLabel.font = NSFont.systemFont(ofSize: 13, weight: isCurrentTrack ? .semibold : .regular)
        self.titleLabel.textColor = isCurrentTrack ? NSColor.systemRed : NSColor.labelColor

        let artistText = song.artistsDisplay.isEmpty ? String(localized: "Unknown Artist") : song.artistsDisplay
        self.artistLabel.stringValue = artistText

        if let duration = song.duration {
            let mins = Int(duration) / 60
            let secs = Int(duration) % 60
            self.durationLabel.stringValue = String(format: "%d:%02d", mins, secs)
        } else {
            self.durationLabel.stringValue = ""
        }

        self.configureAccessibility(title: song.title, artist: artistText, isCurrentTrack: isCurrentTrack)

        let songId = song.id
        self.currentSongId = songId
        self.imageLoadTask?.cancel()
        let primaryURL = song.thumbnailURL?.highQualityThumbnailURL
        let fallbackURL = song.fallbackThumbnailURL
        self.imageLoadTask = Task { [weak self] in
            let targetSize = CGSize(width: 40, height: 40)
            var image: NSImage?
            if let primaryURL {
                image = await ImageCache.shared.image(for: primaryURL, targetSize: targetSize)
            }
            if image == nil, let fallbackURL {
                image = await ImageCache.shared.image(for: fallbackURL, targetSize: targetSize)
            }
            guard !Task.isCancelled, self?.currentSongId == songId else { return }
            self?.thumbnailImageView.image = image
        }
    }

    /// Makes the row a single coherent VoiceOver element. The composed label
    /// reads title, artist, duration, and (when applicable) the now-playing
    /// state; activation plays the song and a custom action removes it.
    /// See P2F019.
    private func configureAccessibility(title: String, artist: String, isCurrentTrack: Bool) {
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.button)

        var components = [title, artist]
        let duration = self.durationLabel.stringValue
        if !duration.isEmpty {
            components.append(duration)
        }
        if isCurrentTrack {
            components.append(String(localized: "Now Playing"))
        }
        self.setAccessibilityLabel(components.joined(separator: ", "))

        // Expose removal as a custom action (only when not the current track,
        // mirroring the context-menu / glass-panel behavior).
        if isCurrentTrack {
            self.setAccessibilityCustomActions([])
        } else {
            let removeAction = NSAccessibilityCustomAction(
                name: String(localized: "Remove from Queue"),
                target: self,
                selector: #selector(self.performAccessibilityRemove)
            )
            self.setAccessibilityCustomActions([removeAction])
        }
    }

    @objc private func performAccessibilityRemove() -> Bool {
        self.onRemove?()
        return true
    }

    /// VoiceOver activation (e.g. Control-Option-Space) plays the row, matching
    /// the click behavior.
    override func accessibilityPerformPress() -> Bool {
        self.onPlay?()
        return true
    }

    func updateAppearance(isCurrentTrack: Bool, isPlaying: Bool, index: Int) {
        self.isCurrentTrack = isCurrentTrack
        self.isPlaying = isPlaying

        if isCurrentTrack {
            // Show animated waveform for current track
            self.indicatorLabel.stringValue = ""
            self.indicatorLabel.isHidden = true

            // Create or update waveform view
            if self.waveformView == nil {
                let waveView = WaveformView(frame: NSRect(x: 0, y: 0, width: 24, height: 16))
                waveView.translatesAutoresizingMaskIntoConstraints = false
                self.waveformView = waveView

                // Find indicator container and add waveform
                if let indicatorContainer = indicatorLabel.superview {
                    indicatorContainer.addSubview(waveView)
                    NSLayoutConstraint.activate([
                        waveView.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
                        waveView.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor),
                        waveView.widthAnchor.constraint(equalToConstant: 24),
                        waveView.heightAnchor.constraint(equalToConstant: 16),
                    ])
                }
            }

            if let waveView = waveformView as? WaveformView {
                waveView.isHidden = false
                waveView.isAnimating = isPlaying
                waveView.tintColor = isPlaying ? NSColor.systemRed : NSColor.tertiaryLabelColor
            }

            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
        } else {
            // Show number for non-current tracks
            self.indicatorLabel.isHidden = false
            self.indicatorLabel.stringValue = "\(index + 1)"
            self.indicatorLabel.textColor = NSColor.tertiaryLabelColor

            // Hide waveform
            self.waveformView?.isHidden = true

            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    @objc private func handleClick() {
        self.onPlay?()
    }

    private func handleTitleClick() {
        if let onNavigateAlbum = self.onNavigateAlbum {
            onNavigateAlbum()
        } else {
            self.onPlay?()
        }
    }

    private func handleArtistClick() {
        if let onNavigateArtist = self.onNavigateArtist {
            onNavigateArtist()
        } else {
            self.onPlay?()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.imageLoadTask?.cancel()
        self.imageLoadTask = nil
        self.currentSongId = nil
        self.thumbnailImageView.image = nil
        self.waveformView?.removeFromSuperview()
        self.waveformView = nil
    }
}

// MARK: - NavigableLabel

/// `NSTextField` that intercepts mouse clicks and shows the pointing-hand
/// cursor while clickable. Used for the queue row's title/artist labels so
/// clicks navigate to album/artist pages instead of playing the row.
@available(macOS 26.0, *)
@MainActor
final class NavigableLabel: NSTextField {
    /// Set to `true` while a navigation closure is wired up — drives both
    /// the cursor affordance and click capturing.
    var isClickable = false {
        didSet {
            self.updateTrackingArea()
            self.window?.invalidateCursorRects(for: self)
        }
    }

    /// Invoked when the label is clicked while `isClickable` is true.
    var onClick: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.isEditable = false
        self.isBordered = false
        self.isSelectable = false
        self.backgroundColor = .clear
        self.refusesFirstResponder = true
    }

    override func mouseDown(with event: NSEvent) {
        guard self.isClickable else {
            super.mouseDown(with: event)
            return
        }
        // Swallow the event so the row's gesture recognizer doesn't also
        // fire. We invoke the click on mouseUp inside our bounds, matching
        // standard button behavior.
        let downPoint = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(downPoint) else {
            super.mouseDown(with: event)
            return
        }

        // Drain to mouseUp to mimic a button press.
        var upEvent: NSEvent?
        let mask: NSEvent.EventTypeMask = [.leftMouseUp, .leftMouseDragged]
        while upEvent == nil {
            guard let next = self.window?.nextEvent(matching: mask) else { break }
            if next.type == .leftMouseUp {
                upEvent = next
            }
        }

        if let upEvent {
            let upPoint = self.convert(upEvent.locationInWindow, from: nil)
            if self.bounds.contains(upPoint) {
                self.onClick?()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        self.updateTrackingArea()
    }

    private func updateTrackingArea() {
        if let trackingArea {
            self.removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard self.isClickable else { return }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        guard self.isClickable else { return }
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with _: NSEvent) {
        guard self.isClickable else { return }
        NSCursor.pop()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if self.isClickable {
            self.addCursorRect(self.bounds, cursor: .pointingHand)
        }
    }
}

// MARK: - WaveformView

@available(macOS 26.0, *)
class WaveformView: NSView {
    var isAnimating: Bool = false {
        didSet {
            self.updateAnimation()
        }
    }

    var tintColor: NSColor = .systemRed {
        didSet {
            layer?.sublayers?.forEach { $0.backgroundColor = self.tintColor.cgColor }
        }
    }

    private var timer: Timer?
    private var bars: [CALayer] = []
    private var startTime: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupBars()
    }

    private func setupBars() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Create 3 bars for the waveform
        let barWidth: CGFloat = 3
        let barSpacing: CGFloat = 2
        let totalWidth = CGFloat(3) * barWidth + CGFloat(2) * barSpacing
        let startX = (bounds.width - totalWidth) / 2

        for i in 0 ..< 3 {
            let bar = CALayer()
            bar.backgroundColor = self.tintColor.cgColor
            bar.cornerRadius = 1
            bar.frame = NSRect(
                x: startX + CGFloat(i) * (barWidth + barSpacing),
                y: bounds.height / 2 - 4,
                width: barWidth,
                height: 8
            )
            layer?.addSublayer(bar)
            self.bars.append(bar)
        }
    }

    private func updateAnimation() {
        if self.isAnimating {
            self.startAnimation()
        } else {
            self.stopAnimation()
            // Reset to static middle position
            for bar in self.bars {
                bar.frame.size.height = 8
                bar.frame.origin.y = (bounds.height - 8) / 2
            }
        }
    }

    private func startAnimation() {
        guard self.timer == nil else { return }

        self.startTime = CACurrentMediaTime()

        // Keep the timer on the main run loop and hop explicitly before touching view state.
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBars()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimation() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private func updateBars() {
        guard self.isAnimating else { return }

        let elapsed = CACurrentMediaTime() - self.startTime
        let barHeights: [CGFloat] = [
            4 + 8 * CGFloat(abs(sin(elapsed * 4))),
            4 + 10 * CGFloat(abs(sin(elapsed * 3 + 1))),
            4 + 6 * CGFloat(abs(sin(elapsed * 5 + 2))),
        ]

        CATransaction.begin()
        CATransaction.setDisableActions(true) // Disable implicit animations
        for (i, bar) in self.bars.enumerated() {
            let height = min(barHeights[i], bounds.height)
            bar.frame.size.height = height
            bar.frame.origin.y = (bounds.height - height) / 2
        }
        CATransaction.commit()
    }

    isolated deinit {
        self.stopAnimation()
    }
}
