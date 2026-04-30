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
            guard let h = p.healthPercent, h >= 5, h <= 100 else { return nil }
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
        let currentHealth = max(min(intercept + slope * now, 100), 0)

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
        guard n > 0 else { return (0, 0, 0) }
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        guard sxx > 0 else { return (0, meanY, 0) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let r2 = syy > 0 ? max(0, min(1, (sxy * sxy) / (sxx * syy))) : 0
        return (slope, intercept, r2)
    }
}
