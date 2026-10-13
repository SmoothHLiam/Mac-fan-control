import Foundation

public struct CurvePoint: Codable, Equatable {
    /// Degrees Celsius.
    public var temp: Double
    /// Percent (0...100) of the fan's min...max RPM range.
    public var percent: Double

    public init(temp: Double, percent: Double) {
        self.temp = temp
        self.percent = percent
    }
}

/// Piecewise-linear temperature -> fan-speed curve.
public struct FanCurve: Codable, Equatable {
    public static let tempRange: ClosedRange<Double> = 30...105
    public static let maxPoints = 8
    public static let minPoints = 2

    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
        normalize()
    }

    /// Sorts, clamps and enforces a monotonic (non-decreasing) speed so a hotter chip never gets a slower fan.
    public mutating func normalize() {
        points = points
            .map { CurvePoint(temp: min(max($0.temp, Self.tempRange.lowerBound), Self.tempRange.upperBound),
                              percent: min(max($0.percent, 0), 100)) }
            .sorted { $0.temp < $1.temp }
        var floor = 0.0
        for i in points.indices {
            points[i].percent = max(points[i].percent, floor)
            floor = points[i].percent
        }
    }

    /// Percent (0...100) for a temperature. Flat before the first point and after the last.
    public func percent(at temp: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if temp <= first.temp { return first.percent }
        if temp >= last.temp { return last.percent }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if temp <= b.temp {
                let span = b.temp - a.temp
                if span <= 0 { return b.percent }
                return a.percent + (b.percent - a.percent) * (temp - a.temp) / span
            }
        }
        return last.percent
    }

    public static let quiet = FanCurve(points: [
        CurvePoint(temp: 45, percent: 0), CurvePoint(temp: 70, percent: 20),
        CurvePoint(temp: 85, percent: 60), CurvePoint(temp: 95, percent: 100),
    ])
    public static let balanced = FanCurve(points: [
        CurvePoint(temp: 40, percent: 0), CurvePoint(temp: 55, percent: 15),
        CurvePoint(temp: 70, percent: 45), CurvePoint(temp: 85, percent: 80),
        CurvePoint(temp: 92, percent: 100),
    ])
    public static let performance = FanCurve(points: [
        CurvePoint(temp: 35, percent: 15), CurvePoint(temp: 50, percent: 40),
        CurvePoint(temp: 65, percent: 75), CurvePoint(temp: 78, percent: 100),
    ])
}
