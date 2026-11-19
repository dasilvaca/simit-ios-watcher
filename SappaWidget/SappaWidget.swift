import SwiftUI
import WidgetKit

// Screen 7 · widgets. They read the JSON snapshot the app writes after each run
// (CoreHost.snapshotURL in the App Group container) and never open the database.

struct Snapshot: Decodable {
    struct Vehicle: Decodable {
        let id: Int64
        let plate: String
        let kind: String
        let nickname: String?
        let pending_fines: UInt32
        let new_fines: UInt32
    }
    struct Deadline: Decodable {
        let plate: String
        let stage: String
        let deadline: Int64
        let business_days_left: UInt32
        let amount: Int64
    }
    let generated_at: Int64
    let status: String // clear | fine | failing | empty
    let last_ok_at: Int64?
    let next_check_at: Int64?
    let new_fines: UInt32
    let vehicles: [Vehicle]
    let next_deadline: Deadline?

    static let placeholder = Snapshot(generated_at: 0, status: "clear", last_ok_at: nil, next_check_at: nil,
                                      new_fines: 0,
                                      vehicles: [Vehicle(id: 1, plate: "ABC12D", kind: "moto", nickname: nil, pending_fines: 0, new_fines: 0)],
                                      next_deadline: nil)

    static func load() -> Snapshot? {
        // Widget bundle id is "<app bundle id>.widget"; the App Group is "group.<app bundle id>".
        let widgetId = Bundle.main.bundleIdentifier ?? ""
        let appId = widgetId.hasSuffix(".widget") ? String(widgetId.dropLast(".widget".count)) : widgetId
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.\(appId)") else { return nil }
        let url = container.appending(path: "Library/Application Support/Sappa/widget-snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: Snapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: Snapshot.load() ?? .placeholder)
        // The app reloads timelines after every run; refresh hourly so "days left" stays current.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

private let rust = Color(red: 0xB4 / 255, green: 0x36 / 255, blue: 0x1C / 255)
private let green = Color(red: 0x1F / 255, green: 0x7A / 255, blue: 0x4D / 255)
private let yellow = Color(red: 0xF5 / 255, green: 0xC5 / 255, blue: 0x18 / 255)

private func displayFont(_ size: CGFloat) -> Font {
    .custom("Space Grotesk", size: size).weight(.bold)
}

struct PlateChipW: View {
    let plate: String
    var body: some View {
        Text(plate)
            .font(displayFont(13)).tracking(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(yellow))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1.5))
            .fixedSize()
    }
}

struct SmallView: View {
    let s: Snapshot
    var body: some View {
        if let d = s.next_deadline, s.status == "fine" {
            VStack(alignment: .leading, spacing: 6) {
                PlateChipW(plate: d.plate)
                Spacer()
                Text("\(Int(d.business_days_left)) days").font(displayFont(30)).foregroundStyle(rust)
                Text(d.stage == "fifty" ? "to pay with 50% off" : "to pay with 25% off")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: s.status == "failing" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title).foregroundStyle(s.status == "failing" ? .orange : green)
                Spacer()
                Text(s.status == "failing" ? "Checks failing" : "All clear").font(displayFont(18))
                if let v = s.vehicles.first, let at = s.last_ok_at {
                    Text("\(v.plate) · \(Date(timeIntervalSince1970: TimeInterval(at)).formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MediumView: View {
    let s: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAPPA").font(displayFont(15))
                Spacer()
                if let next = s.next_check_at {
                    Text("Next: \(Date(timeIntervalSince1970: TimeInterval(next)).formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(s.vehicles.prefix(3), id: \.id) { v in
                HStack {
                    PlateChipW(plate: v.plate)
                    Text(v.nickname ?? "").font(.subheadline).lineLimit(1)
                    Spacer()
                    if v.new_fines > 0 {
                        Text("\(Int(v.new_fines)) new").font(.caption.bold()).foregroundStyle(rust)
                    } else if v.pending_fines > 0 {
                        Text("\(Int(v.pending_fines)) pending").font(.caption.bold()).foregroundStyle(rust)
                    } else {
                        Text("No fines").font(.caption.bold()).foregroundStyle(green)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct LockView: View {
    let s: Snapshot
    var body: some View {
        if let v = s.vehicles.first(where: { $0.new_fines > 0 }) {
            Label("\(Int(v.new_fines)) new on \(v.plate)", systemImage: "exclamationmark.triangle")
        } else if s.status == "failing" {
            Label("Checks failing", systemImage: "exclamationmark.triangle")
        } else {
            Label("All clear", systemImage: "checkmark.circle")
        }
    }
}

struct SappaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: MediumView(s: entry.snapshot)
            case .accessoryRectangular, .accessoryInline: LockView(s: entry.snapshot)
            default: SmallView(s: entry.snapshot)
            }
        }
        .containerBackground(for: .widget) {
            entry.snapshot.status == "fine" ? rust.opacity(0.12) : green.opacity(0.10)
        }
    }
}

@main
struct SappaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SappaStatus", provider: Provider()) { entry in
            SappaWidgetView(entry: entry)
        }
        .configurationDisplayName("SAPPA")
        .description("Your plates’ status on SIMIT.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
