import Foundation

/// Batches step changes and uploads them to HCGateway when the treadmill stops.
///
/// Upload triggers when ALL conditions are met:
/// 1. A speed change occurred (hasSpeedChange)
/// 2. Accumulated steps >= 10 (avoids noise)
/// 3. Previous speed was non-zero (was actively walking)
/// 4. New speed is zero (treadmill just stopped or paused)
///
/// On successful upload, resets the accumulator. On failure, steps are retained
/// for the next upload attempt.
class StepsUploader {
    private var hcGatewayService: HCGatewayService

    private var accumulatedSteps: Int = 0
    private var startTime: Date? = nil

    init(hcGatewayService: HCGatewayService) {
        self.hcGatewayService = hcGatewayService
    }

    /// Accumulates steps from each BLE state change and triggers upload when the treadmill stops.
    func handleChange(_ change: Change) {
        let hasSpeedChange = change.newSpeed != change.oldSpeed
        accumulatedSteps += change.stepsDiff

        if self.startTime == nil {
            self.startTime = Date()
        }
        
        if !hasSpeedChange || accumulatedSteps < 10 || change.oldSpeed == 0 || change.newSpeed != 0 {
            return
        }

        guard let startTime = self.startTime else { return }
        let now = Date()
        
        print("uploading \(startTime)-\(now) => \(self.accumulatedSteps)")
        
        Task {
            let success = await hcGatewayService.uploadSteps(startTime: startTime, endTime: now, steps: self.accumulatedSteps)
            if success {
                print("Steps uploaded successfully to HCGateway.")
                self.reset()
            } else {
                print("Failed to upload steps to HCGateway.")
            }
        }
        
    }
    
    func reset() {
        self.startTime = nil
        self.accumulatedSteps = 0
    }
}
