import Foundation

struct HealthForecast {
    let currentHealth: Double
    let slopePerDay: Double
    let dateAtThreshold: Date?
    let cyclesPerDay: Double?
    let cyclesUntilThreshold: Int?
    let confidence: Double
}

struct HealthAnomaly {
    let deltaPercent: Double
    let windowDays: Int
}

enum HealthAnalytics {
    static func forecast(points: [HistoryPoint], threshold: Double = 80.0) -> HealthForecast? {
        let pts = points.compactMap { p -> (Date, Double, Int?)? in
            guard let h = p.healthPercent, h > 50, h <= 105 else { return nil }
            return (p.timestamp, h, p.cycleCount)
        }
        guard pts.count >= 8 else { return nil }
        guard let first = pts.first, let last = pts.last else { return nil }
        let span = last.0.timeIntervalSince(first.0)
        guard span >= 86400 else { return nil }

        let xs = pts.map { $0.0.timeIntervalSince(first.0) / 86400.0 }
        let ys = pts.map { $0.1 }
        let (slope, intercept, r2) = linearRegression(xs: xs, ys: ys)
        guard r2 >= 0.0 else { return nil }

        let now = Date().timeIntervalSince(first.0) / 86400.0
        let currentHealth = max(min(intercept + slope * now, 105), 0)

        var thresholdDate: Date?
        if slope < -0.001 {
            let xAtThreshold = (threshold - intercept) / slope
            if xAtThreshold > now, xAtThreshold < now + 365 * 20 {
                thresholdDate = first.0.addingTimeInterval(xAtThreshold * 86400)
            }
        }

        var cyclesPerDay: Double?
        var cyclesUntilThreshold: Int?
        let cycleSamples = pts.compactMap { p -> (Date, Int)? in
            guard let c = p.2, c > 0 else { return nil }
            return (p.0, c)
        }
        if let f = cycleSamples.first, let l = cycleSamples.last,
           l.1 > f.1, l.0.timeIntervalSince(f.0) > 86400 {
            let days = l.0.timeIntervalSince(f.0) / 86400
            let perDay = Double(l.1 - f.1) / days
            cyclesPerDay = perDay
            if let date = thresholdDate, perDay > 0 {
                let daysAhead = date.timeIntervalSinceNow / 86400
                cyclesUntilThreshold = Int(daysAhead * perDay)
            }
        }

        return HealthForecast(
            currentHealth: currentHealth,
            slopePerDay: slope,
            dateAtThreshold: thresholdDate,
            cyclesPerDay: cyclesPerDay,
            cyclesUntilThreshold: cyclesUntilThreshold,
            confidence: max(0, min(1, r2))
        )
    }

    static func anomaly(points: [HistoryPoint], windowDays: Int = 7,
                       deltaThreshold: Double = 2.0) -> HealthAnomaly? {
        let cutoff = Date().addingTimeInterval(-Double(windowDays) * 86400)
        let recent = points.filter { $0.timestamp >= cutoff }.compactMap(\.healthPercent)
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return nil }
        let delta = first - last
        if delta >= deltaThreshold {
            return HealthAnomaly(deltaPercent: delta, windowDays: windowDays)
        }
        return nil
    }

    private static func linearRegression(xs: [Double], ys: [Double]) -> (Double, Double, Double) {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return (0, sumY / n, 0) }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        let meanY = sumY / n
        let ssTot = ys.map { ($0 - meanY) * ($0 - meanY) }.reduce(0, +)
        let ssRes = zip(xs, ys).map { (x, y) -> Double in
            let pred: Double = slope * x + intercept
            let d: Double = y - pred
            return d * d
        }.reduce(0.0, +)
        let r2 = ssTot > 0 ? 1 - ssRes / ssTot : 0
        return (slope, intercept, r2)
    }
}
