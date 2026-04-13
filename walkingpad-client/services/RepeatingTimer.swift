import Foundation

/// Simple timer wrapper that fires a callback on a repeating interval on the main RunLoop.
class RepeatingTimer {
    private var interval: TimeInterval;
    private var eventHandler: () -> Void;
    private var timer: Timer? = nil
    
    init(interval: TimeInterval, eventHandler: @escaping ()-> Void) {
        self.interval = interval;
        self.eventHandler = eventHandler;
    }
    
    func start() {
        if (self.timer != nil) {
            appLog("Timer is already running.")
            return;
        }
        
        appLog("Starting timer");
        let newTimer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { _ in
            self.eventHandler()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        self.timer = newTimer;
    }
    
    func stop() {
        guard let startedTimer = self.timer else {
            appLog("Cannot stop timer, as it is not yet started")
            return;
        }
        
        appLog("Stopping timer");
        startedTimer.invalidate();
        self.timer = nil;
    }
}
