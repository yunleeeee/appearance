import Foundation

/// State values for the current vine appearance.
public enum VinePhase: String, Codable, Sendable {
    case hidden, appearing, swaying, receiving, disappearing, full
}

public struct VineBranch: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var count: Int
    public var isMature: Bool { count >= VineEngine.grapesPerBranchLimit }
    public init(id: String, count: Int) { self.id = id; self.count = count }
}

public struct VineGrowth: Codable, Equatable, Sendable {
    public let category: String
    public let grapeIndex: Int
    public let sequence: UInt64
    public init(category: String, grapeIndex: Int, sequence: UInt64) {
        self.category = category; self.grapeIndex = grapeIndex; self.sequence = sequence
    }
}

public struct VineTheft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let category: String
    public let branchIndex: Int
    public let startedAt: Date
    public let isPreview: Bool
    public init(id: UUID, category: String, branchIndex: Int, startedAt: Date, isPreview: Bool) {
        self.id = id; self.category = category; self.branchIndex = branchIndex
        self.startedAt = startedAt; self.isPreview = isPreview
    }
}

/// A value snapshot of the vine appearance.
public struct VineSnapshot: Codable, Equatable, Sendable {
    public let phase: VinePhase
    public let branches: [VineBranch]
    public let latestGrowth: VineGrowth?
    public let activeTheft: VineTheft?
    public let isVisible: Bool
    public let isFull: Bool
    public let recordedBranches: [VineBranch]
    public let harvestedCounts: [String: Int]
    public let persistenceError: String?
    public init(phase: VinePhase, branches: [VineBranch], latestGrowth: VineGrowth?,
                activeTheft: VineTheft?, isVisible: Bool, isFull: Bool,
                recordedBranches: [VineBranch], harvestedCounts: [String: Int],
                persistenceError: String? = nil) {
        self.phase = phase; self.branches = branches; self.latestGrowth = latestGrowth
        self.activeTheft = activeTheft; self.isVisible = isVisible; self.isFull = isFull
        self.recordedBranches = recordedBranches; self.harvestedCounts = harvestedCounts
        self.persistenceError = persistenceError
    }
}
