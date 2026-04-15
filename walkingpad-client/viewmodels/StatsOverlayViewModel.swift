import SwiftUI
import Combine

class StatsOverlayViewModel: ObservableObject {
    @Published var speed: String = "0.0"
    @Published var distance: String = "0.00"
    @Published var time: String = "0:00"
    @Published var isRunning: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    private let workout: Workout
    private let walkingPadService: WalkingPadService
    
    init(workout: Workout, walkingPadService: WalkingPadService) {
        self.workout = workout
        self.walkingPadService = walkingPadService
        
        setupSubscriptions()
        setupTimer()
    }
    
    private func setupTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if self?.isRunning == true {
                    self?.updateStats()
                }
            }
    }
    
    private func setupSubscriptions() {
        // Observe speed from walkingPadService
        walkingPadService.$lastState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSpeed()
            }
            .store(in: &cancellables)
        
        // Observe session distance from workout
        workout.$sessionDistance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStats()
            }
            .store(in: &cancellables)
            
        // Initial update
        updateSpeed()
        updateStats()
    }
    
    private func updateSpeed() {
        let state = walkingPadService.lastStatus()
        let speedVal = Double(state?.speed ?? 0) / 10.0
        self.speed = String(format: "%.1f", speedVal)
        self.isRunning = speedVal > 0
        self.updateStats()
    }
    
    private func updateStats() {
        let dist = Double(workout.sessionDistance) / 1000.0
        self.distance = String(format: "%.2f", dist)
        
        let elapsed = workout.currentSessionStartTime.map {
            Int(Date().timeIntervalSince($0))
        } ?? 0
        
        let mins = elapsed / 60
        let secs = elapsed % 60
        self.time = String(format: "%d:%02d", mins, secs)
    }
}
