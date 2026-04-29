import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct HistoryPoint {
    let timestamp: Date
    let chargePercent: Double?
    let healthPercent: Double?
    let cycleCount: Int?
    let currentCapacity: Int?
    let maxCapacity: Int?
    let voltage: Double?
    let amperage: Double?
    let wattage: Double?
    let temperature: Double?
    let isCharging: Bool?
}

final class HistoryStore {
    static let shared = HistoryStore()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "history.store")

    private init() {
        guard let dir = supportDir() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("history.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { return }
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS snapshots(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              device_id TEXT NOT NULL,
              ts REAL NOT NULL,
              charge_pct REAL,
              health_pct REAL,
              cycle_count INTEGER,
              current_cap INTEGER,
              max_cap INTEGER,
              voltage REAL,
              amperage REAL,
              wattage REAL,
              temperature REAL,
              is_charging INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_dev_ts ON snapshots(device_id, ts);
        """, nil, nil, nil)
    }

    func dbPath() -> String? { supportDir()?.appendingPathComponent("history.sqlite").path }

    func recordMac(_ s: BatterySnapshot) {
        record(deviceId: "mac",
               ts: s.timestamp,
               charge: s.nominalChargePercent,
               health: s.healthPercent,
               cycles: s.cycleCount,
               curCap: s.currentCapacity,
               maxCap: s.maxCapacity,
               voltage: s.voltageV,
               amperage: s.amperageA,
               wattage: s.wattage,
               temperature: s.temperatureC,
               charging: s.isCharging)
    }

    func recordIOS(udid: String, snapshot s: IOSBatterySnapshot) {
        record(deviceId: udid,
               ts: s.timestamp,
               charge: Double(s.chargePercent),
               health: s.healthPercent,
               cycles: s.cycleCount,
               curCap: s.absoluteCapacity,
               maxCap: s.nominalCapacity,
               voltage: s.voltageV,
               amperage: s.amperageA,
               wattage: nil,
               temperature: s.temperatureC,
               charging: s.isCharging)
    }

    private func record(deviceId: String, ts: Date, charge: Double?, health: Double?,
                        cycles: Int?, curCap: Int?, maxCap: Int?, voltage: Double?,
                        amperage: Double?, wattage: Double?, temperature: Double?,
                        charging: Bool?) {
        queue.async {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            let sql = """
                INSERT INTO snapshots(device_id, ts, charge_pct, health_pct, cycle_count,
                  current_cap, max_cap, voltage, amperage, wattage, temperature, is_charging)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?);
            """
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, deviceId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, ts.timeIntervalSince1970)
            self.bindOpt(stmt, 3, charge)
            self.bindOpt(stmt, 4, health)
            self.bindOptInt(stmt, 5, cycles)
            self.bindOptInt(stmt, 6, curCap)
            self.bindOptInt(stmt, 7, maxCap)
            self.bindOpt(stmt, 8, voltage)
            self.bindOpt(stmt, 9, amperage)
            self.bindOpt(stmt, 10, wattage)
            self.bindOpt(stmt, 11, temperature)
            if let c = charging { sqlite3_bind_int(stmt, 12, c ? 1 : 0) }
            else { sqlite3_bind_null(stmt, 12) }
            sqlite3_step(stmt)
        }
    }

    func points(deviceId: String, since: Date) -> [HistoryPoint] {
        var result: [HistoryPoint] = []
        queue.sync {
            guard let db = self.db else { return }
            var stmt: OpaquePointer?
            let sql = """
                SELECT ts, charge_pct, health_pct, cycle_count, current_cap, max_cap,
                       voltage, amperage, wattage, temperature, is_charging
                FROM snapshots WHERE device_id = ? AND ts >= ? ORDER BY ts ASC;
            """
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, deviceId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970)
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(HistoryPoint(
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                    chargePercent: optDouble(stmt, 1),
                    healthPercent: optDouble(stmt, 2),
                    cycleCount: optInt(stmt, 3),
                    currentCapacity: optInt(stmt, 4),
                    maxCapacity: optInt(stmt, 5),
                    voltage: optDouble(stmt, 6),
                    amperage: optDouble(stmt, 7),
                    wattage: optDouble(stmt, 8),
                    temperature: optDouble(stmt, 9),
                    isCharging: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil
                        : sqlite3_column_int(stmt, 10) != 0
                ))
            }
        }
        return result
    }

    func exportCSV(deviceId: String) -> URL? {
        let pts = points(deviceId: deviceId, since: Date(timeIntervalSince1970: 0))
        let df = ISO8601DateFormatter()
        var lines = ["timestamp,charge_pct,health_pct,cycle_count,current_cap,max_cap,voltage,amperage,wattage,temperature,is_charging"]
        for p in pts {
            var cols: [String] = []
            cols.append(df.string(from: p.timestamp))
            cols.append(p.chargePercent.map { String($0) } ?? "")
            cols.append(p.healthPercent.map { String($0) } ?? "")
            cols.append(p.cycleCount.map { String($0) } ?? "")
            cols.append(p.currentCapacity.map { String($0) } ?? "")
            cols.append(p.maxCapacity.map { String($0) } ?? "")
            cols.append(p.voltage.map { String($0) } ?? "")
            cols.append(p.amperage.map { String($0) } ?? "")
            cols.append(p.wattage.map { String($0) } ?? "")
            cols.append(p.temperature.map { String($0) } ?? "")
            cols.append(p.isCharging.map { $0 ? "1" : "0" } ?? "")
            lines.append(cols.joined(separator: ","))
        }
        guard let dir = supportDir() else { return nil }
        let safe = deviceId.replacingOccurrences(of: "/", with: "_")
        let url = dir.appendingPathComponent("export-\(safe)-\(Int(Date().timeIntervalSince1970)).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func bindOpt(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Double?) {
        if let v = v, v.isFinite { sqlite3_bind_double(stmt, idx, v) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func bindOptInt(_ stmt: OpaquePointer?, _ idx: Int32, _ v: Int?) {
        if let v = v { sqlite3_bind_int64(stmt, idx, sqlite3_int64(v)) }
        else { sqlite3_bind_null(stmt, idx) }
    }

    private func optDouble(_ stmt: OpaquePointer?, _ idx: Int32) -> Double? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, idx)
    }

    private func optInt(_ stmt: OpaquePointer?, _ idx: Int32) -> Int? {
        sqlite3_column_type(stmt, idx) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, idx))
    }

    private func supportDir() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DoctorBattery", isDirectory: true)
    }
}
