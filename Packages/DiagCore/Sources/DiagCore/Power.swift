import Foundation

public enum PowerMath {
    /// Power in kW from torque (N·m) and engine speed (rpm).
    public static func kilowatts(torque: Double, rpm: Double) -> Double {
        torque * rpm / 9549
    }

    /// Metric horsepower ("chevaux"), as used on French registration papers.
    public static func horsepower(kilowatts: Double) -> Double {
        kilowatts * 1.35962
    }
}

/// Estimates power at the wheels from how fast the car gains speed.
/// The OBD speed is a whole number of km/h, so the acceleration is taken as the
/// slope of a straight line through the last second of readings.
public struct AccelerationPowerEstimator: Sendable {
    public var massKg: Double
    /// Drag coefficient times frontal area, about right for a compact MPV.
    public var dragArea = 0.8
    public var rollingResistance = 0.012
    public var window: TimeInterval = 1.2

    private var samples: [(time: TimeInterval, speed: Double)] = []

    public init(massKg: Double) {
        self.massKg = massKg
    }

    /// Adds a speed reading and returns the wheel power in kW, or nil while the
    /// car is not clearly accelerating.
    public mutating func add(speedKmh: Double, at time: TimeInterval) -> Double? {
        samples.append((time, speedKmh / 3.6))
        samples.removeAll { time - $0.time > window }
        guard samples.count >= 4, let first = samples.first, time - first.time >= window * 0.6 else { return nil }

        let meanTime = samples.map(\.time).reduce(0, +) / Double(samples.count)
        let meanSpeed = samples.map(\.speed).reduce(0, +) / Double(samples.count)
        let covariance = samples.reduce(0) { $0 + ($1.time - meanTime) * ($1.speed - meanSpeed) }
        let variance = samples.reduce(0) { $0 + ($1.time - meanTime) * ($1.time - meanTime) }
        guard variance > 0 else { return nil }

        let acceleration = covariance / variance
        let speed = meanSpeed
        guard acceleration > 0.3, speed > 3 else { return nil }

        let inertia = massKg * acceleration * speed
        let drag = 0.5 * 1.2 * dragArea * pow(speed, 3)
        let rolling = rollingResistance * massKg * 9.81 * speed
        return (inertia + drag + rolling) / 1000
    }

    public mutating func reset() {
        samples = []
    }
}
