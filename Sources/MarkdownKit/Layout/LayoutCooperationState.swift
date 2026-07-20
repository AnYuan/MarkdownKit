import Foundation

struct LayoutCooperationState {
    enum WorkKind {
        case solver
        case planning
        case materialization
    }

    private static let solverYieldInterval = 16
    private static let planningYieldInterval = 64
    private static let materializationYieldInterval = 32

    private var solverWorkItems = 0
    private var planningWorkItems = 0
    private var materializationWorkItems = 0

    mutating func shouldYield(after workKind: WorkKind) -> Bool {
        switch workKind {
        case .solver:
            return Self.increment(
                &solverWorkItems,
                interval: Self.solverYieldInterval
            )
        case .planning:
            return Self.increment(
                &planningWorkItems,
                interval: Self.planningYieldInterval
            )
        case .materialization:
            return Self.increment(
                &materializationWorkItems,
                interval: Self.materializationYieldInterval
            )
        }
    }

    private static func increment(_ counter: inout Int, interval: Int) -> Bool {
        counter += 1
        guard counter >= interval else { return false }
        counter = 0
        return true
    }
}
