import Foundation

/// Sent between the iPhone and the Watch over the mirrored workout session.
/// The Watch app has its own copy (SetCounterWatch/WatchMessage.swift); keep them in sync.
struct WatchMessage: Codable, Equatable {
    enum Command: String, Codable {
        /// Save the Watch workout and stop.
        case end
        /// Throw the Watch workout away (no sets were done).
        case discard
    }

    /// Watch → iPhone: the latest heart rate.
    var bpm: Int?
    /// iPhone → Watch: what the workout is doing now.
    var command: Command?
    var exercise: String?
    var setsDone: Int?
    var setsTotal: Int?
    /// When the current rest ends; the Watch taps the wrist then.
    var restEnd: Date?
}
