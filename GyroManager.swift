import Foundation
import CoreMotion

class GyroManager: ObservableObject {
    private var motion = CMMotionManager()
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var yaw: Double = 0.0

    init() {
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.05
            motion.startDeviceMotionUpdates(to: .main) { data, error in
                guard let attitude = data?.attitude else { return }
                DispatchQueue.main.async {
                    self.pitch = attitude.pitch
                    self.roll = attitude.roll
                    self.yaw = attitude.yaw
                }
            }
        }
    }
}
