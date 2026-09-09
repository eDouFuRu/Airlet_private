import Foundation

/// Only the currently displayed notification may carry text. Nothing here is persisted.
public struct HiNotificationNotice: Equatable, Identifiable, Sendable {
    public let id: String
    public let sender: String?
    public let body: String?
    public let count: Int
    public let receivedAt: TimeInterval
    public let sourceBundleID: String
}

public struct HiNotificationCandidate: Equatable, Sendable {
    /// A process-local, opaque AX-card/content identity; never a raw message string.
    public let identity: String
    public let sender: String?
    public let body: String?
    public let sourceBundleID: String

    public init(identity: String, sender: String?, body: String?,
                sourceBundleID: String = HiNotificationSourceEvidence.hiBundleID) {
        self.identity = identity
        self.sender = sender
        self.body = body
        self.sourceBundleID = sourceBundleID
    }
}

/// Attribution must come from the system banner's metadata, never its message body.
public struct HiNotificationSourceEvidence: Equatable, Sendable {
    public static let hiBundleID = "com.electron.redcity"
    public var sourceBundleIDs: Set<String>
    /// The banner's whole AXAttributedDescription, not a pre-sliced application name.
    public var bannerDescriptions: Set<String>
    public var hasGroupedContent: Bool
    public var hasMultipleCards: Bool

    public init(sourceBundleIDs: Set<String> = [], bannerDescriptions: Set<String> = [],
                hasGroupedContent: Bool = false, hasMultipleCards: Bool = false) {
        self.sourceBundleIDs = sourceBundleIDs
        self.bannerDescriptions = bannerDescriptions
        self.hasGroupedContent = hasGroupedContent
        self.hasMultipleCards = hasMultipleCards
    }

    public func isUnambiguouslyHi(knownDisplayNames: Set<String>) -> Bool {
        isUnambiguouslySource(bundleID: Self.hiBundleID, knownDisplayNames: knownDisplayNames)
    }

    public func isUnambiguouslySource(bundleID: String, knownDisplayNames: Set<String>) -> Bool {
        guard !bundleID.isEmpty, !hasGroupedContent, !hasMultipleCards else { return false }
        guard sourceBundleIDs.isSubset(of: [bundleID]) else { return false }
        guard !bannerDescriptions.isEmpty else { return sourceBundleIDs == [bundleID] }
        return bannerDescriptions.allSatisfy { Self.matchedDisplayName(in: $0, candidates: knownDisplayNames) != nil }
    }

    /// macOS renders a banner description as "<Application> <title>, <subtitle>, <body>":
    /// the application name is separated from the title by a plain space, so it cannot be
    /// recovered by slicing at the first comma. Match a known name against the prefix instead.
    public static func matchedDisplayName(in description: String, candidates: Set<String>) -> String? {
        let text = normalized(description)
        guard !text.isEmpty else { return nil }
        var best: String?
        var ambiguous = false
        for candidate in candidates {
            let name = normalized(candidate)
            guard !name.isEmpty, name.count <= 80, text.hasPrefix(name) else { continue }
            let boundary = text.index(text.startIndex, offsetBy: name.count)
            guard boundary == text.endIndex || Self.separators.contains(text[boundary]) else { continue }
            guard let current = best else { best = name; continue }
            if name.count > current.count { best = name; ambiguous = false }
            else if name.count == current.count, name != current { ambiguous = true }
        }
        return ambiguous ? nil : best
    }

    private static let separators: Set<Character> = [" ", ",", "，", "\u{00A0}", "\u{3000}", "\n"]

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Deterministic privacy/dedup reducer. Presentation duration and hover belong to the shell.
public struct HiNotificationState: Equatable, Sendable {
    public static let burstWindow: TimeInterval = 5
    public static let dedupLifetime: TimeInterval = 30
    public static let maxRecentIdentities = 64
    public private(set) var current: HiNotificationNotice?
    public private(set) var enabledSources: Set<String> = []
    public private(set) var detailedSources: Set<String> = []
    public var isEnabled: Bool { !enabledSources.isEmpty }
    public private(set) var applicationAvailable = false
    public var isDetailed: Bool { detailedSources.contains(HiNotificationSourceEvidence.hiBundleID) }
    private var recentIdentities: [String: TimeInterval] = [:]
    public var recentIdentityCount: Int { recentIdentities.count }

    public init() {}

    public mutating func setEnabled(_ enabled: Bool) {
        configure(enabled: enabled ? [HiNotificationSourceEvidence.hiBundleID] : [], detailed: detailedSources)
    }

    public mutating func setApplicationAvailable(_ available: Bool) {
        applicationAvailable = available
        if !available { dismiss() }
    }

    public mutating func setDetailed(_ detailed: Bool) {
        var sources = detailedSources
        if detailed { sources.insert(HiNotificationSourceEvidence.hiBundleID) }
        else { sources.remove(HiNotificationSourceEvidence.hiBundleID) }
        configure(enabled: enabledSources, detailed: sources)
    }

    /// Per-application opt-in. Existing hi setters remain compatible with v1 preferences.
    public mutating func configure(enabled: Set<String>, detailed: Set<String>) {
        enabledSources = enabled
        detailedSources = detailed
        if enabled.isEmpty { clear(); return }
        guard let old = current else { return }
        if !enabled.contains(old.sourceBundleID) { dismiss(); return }
        if !detailed.contains(old.sourceBundleID) {
            current = HiNotificationNotice(id: old.id, sender: nil, body: nil,
                                           count: old.count, receivedAt: old.receivedAt,
                                           sourceBundleID: old.sourceBundleID)
        }
    }

    @discardableResult
    public mutating func receive(_ candidate: HiNotificationCandidate, now: TimeInterval) -> Bool {
        guard enabledSources.contains(candidate.sourceBundleID), applicationAvailable, now.isFinite, !candidate.identity.isEmpty else { return false }
        recentIdentities = recentIdentities.filter { now >= $0.value && now - $0.value <= Self.dedupLifetime }
        let dedupIdentity = candidate.sourceBundleID + "\u{0}" + candidate.identity
        guard recentIdentities[dedupIdentity] == nil else { return false }
        recentIdentities[dedupIdentity] = now
        if recentIdentities.count > Self.maxRecentIdentities,
           let oldest = recentIdentities.min(by: { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value })?.key {
            recentIdentities.removeValue(forKey: oldest)
        }
        let count: Int
        if let old = current, old.sourceBundleID == candidate.sourceBundleID, now >= old.receivedAt, now - old.receivedAt <= Self.burstWindow {
            count = min(999, old.count + 1)
        } else {
            count = 1
        }
        current = HiNotificationNotice(id: candidate.identity,
                                       sender: detailedSources.contains(candidate.sourceBundleID) ? Self.displayText(candidate.sender, limit: 80) : nil,
                                       body: detailedSources.contains(candidate.sourceBundleID) ? Self.displayText(candidate.body, limit: 240) : nil,
                                       count: count, receivedAt: now, sourceBundleID: candidate.sourceBundleID)
        return true
    }

    /// A system card can populate title/body after its AX-created event. Refreshing that
    /// same card must not count another message, extend its lifetime, or restore private text.
    public mutating func refreshCurrentContent(_ candidate: HiNotificationCandidate) {
        guard enabledSources.contains(candidate.sourceBundleID), applicationAvailable, detailedSources.contains(candidate.sourceBundleID),
              let old = current, old.id == candidate.identity, old.sourceBundleID == candidate.sourceBundleID else { return }
        current = HiNotificationNotice(id: old.id,
                                       sender: Self.displayText(candidate.sender, limit: 80),
                                       body: Self.displayText(candidate.body, limit: 240),
                                       count: old.count, receivedAt: old.receivedAt, sourceBundleID: old.sourceBundleID)
    }

    /// Keep opaque recent identities so a delayed AX callback cannot replay a dismissed card.
    public mutating func dismiss() { current = nil }

    public mutating func clear() {
        current = nil
        recentIdentities.removeAll(keepingCapacity: false)
    }

    private static func displayText(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let cleaned = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" })
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return cleaned.isEmpty ? nil : String(cleaned.prefix(limit))
    }
}
