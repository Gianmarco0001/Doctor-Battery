import SwiftUI

extension Color {
    static let dbBg = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let dbBg2 = Color(red: 0.040, green: 0.040, blue: 0.045)
    static let dbSurface = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let dbSurface2 = Color(red: 0.102, green: 0.102, blue: 0.118)
    static let dbBorder = Color(white: 1.0, opacity: 0.08)
    static let dbBorderStrong = Color(white: 1.0, opacity: 0.14)
    static let dbText = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let dbText2 = Color(red: 0.631, green: 0.631, blue: 0.651)
    static let dbText3 = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let dbAccent = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let dbAccent2 = Color(red: 0.0, green: 0.831, blue: 1.0)
    static let dbWarn = Color(red: 1.0, green: 0.624, blue: 0.039)
    static let dbBad = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let dbGlow = Color(red: 0.188, green: 0.820, blue: 0.345, opacity: 0.45)
}

struct DBCard: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(elevated ? Color.dbSurface2 : Color.dbSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.dbBorder, lineWidth: 1)
            )
    }
}

struct DBSidebarItem: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.dbAccent.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? Color.dbAccent.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(selected ? Color.dbAccent : Color.dbText2)
    }
}

extension View {
    func dbCard(elevated: Bool = false) -> some View { modifier(DBCard(elevated: elevated)) }
    func dbSidebarItem(selected: Bool) -> some View { modifier(DBSidebarItem(selected: selected)) }
}

struct DBLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.subheadline))
            .foregroundStyle(Color.dbText2)
    }
}

struct DBValue: View {
    let text: String
    var color: Color = .dbAccent
    var size: CGFloat = 16
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
    }
}

struct DBKVRow: View {
    let label: String
    let value: String
    var valueColor: Color = .dbText
    var body: some View {
        HStack {
            DBLabel(text: label)
            Spacer()
            DBValue(text: value, color: valueColor)
        }
    }
}

struct DBAurora: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.dbAccent.opacity(0.18))
                .frame(width: 700, height: 700)
                .blur(radius: 120)
                .offset(x: -250, y: -300)
            Circle()
                .fill(Color.dbAccent2.opacity(0.10))
                .frame(width: 600, height: 600)
                .blur(radius: 110)
                .offset(x: 280, y: 250)
            Circle()
                .fill(Color.dbAccent.opacity(0.08))
                .frame(width: 500, height: 500)
                .blur(radius: 90)
                .offset(x: 100, y: -120)
        }
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
    }
}

struct DBStatCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.dbText3)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.dbSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.dbBorder, lineWidth: 1)
        )
    }
}

struct DBMiniRing: View {
    let percent: Double
    var size: CGFloat = 36
    var color: Color = .dbAccent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, percent / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 6)
                .animation(.easeInOut(duration: 0.6), value: percent)
        }
        .frame(width: size, height: size)
    }
}

struct DBChargeGauge: View {
    let percent: Double
    let charging: Bool
    var size: CGFloat = 140

    private var color: Color {
        if percent < 20 { return .dbBad }
        if percent < 40 { return .dbWarn }
        return .dbAccent
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, percent / 100)))
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.7), color],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 12)
                .animation(.easeInOut(duration: 0.6), value: percent)
            VStack(spacing: 2) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(color)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(String(format: "%.0f", percent))
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.dbText)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .foregroundStyle(Color.dbText2)
            }
        }
        .frame(width: size, height: size)
    }
}

struct DBSquareIcon: View {
    let symbol: String
    var color: Color = .dbText2
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.dbSurface2)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.dbBorder, lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

enum SystemInfo {
    static let macChip: String = {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let raw = String(cString: buf)
        if let r = raw.range(of: "Apple ") {
            return String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if raw.contains("Intel") { return "Intel" }
        return raw.components(separatedBy: " ").first ?? "Mac"
    }()

    static func iosChip(productType: String) -> String? {
        let map: [String: String] = [
            "iPhone16,2": "A17 Pro", "iPhone16,1": "A17 Pro",
            "iPhone15,5": "A16", "iPhone15,4": "A16",
            "iPhone15,3": "A16", "iPhone15,2": "A16",
            "iPhone14,8": "A15", "iPhone14,7": "A15",
            "iPhone14,6": "A15", "iPhone14,5": "A15",
            "iPhone14,4": "A15", "iPhone14,3": "A15",
            "iPhone14,2": "A15",
            "iPhone13,4": "A14", "iPhone13,3": "A14",
            "iPhone13,2": "A14", "iPhone13,1": "A14",
            "iPhone12,8": "A13", "iPhone12,5": "A13",
            "iPhone12,3": "A13", "iPhone12,1": "A13",
            "iPad14,11": "M4", "iPad14,10": "M4",
            "iPad14,6": "M2", "iPad14,5": "M2",
            "iPad14,4": "M2", "iPad14,3": "M2",
            "iPad13,18": "A15", "iPad13,17": "A15",
            "iPad13,11": "M1", "iPad13,10": "M1",
            "iPad13,9": "M1", "iPad13,8": "M1",
            "iPad13,7": "M1", "iPad13,6": "M1",
            "iPad13,5": "M1", "iPad13,4": "M1",
            "iPad13,2": "A14", "iPad13,1": "A14",
            "iPad12,2": "A13", "iPad12,1": "A13",
            "iPad11,7": "A12", "iPad11,6": "A12",
            "iPad11,4": "A12", "iPad11,3": "A12",
            "iPad11,2": "A12", "iPad11,1": "A12"
        ]
        return map[productType]
    }
}

struct DBSectionHeader: View {
    let title: String
    var icon: String?
    var body: some View {
        HStack(spacing: 8) {
            if let i = icon {
                Image(systemName: i)
                    .foregroundStyle(Color.dbAccent)
                    .font(.system(size: 14, weight: .medium))
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dbText2)
                .textCase(.uppercase)
                .tracking(1.2)
            Spacer()
        }
        .padding(.bottom, 4)
    }
}
