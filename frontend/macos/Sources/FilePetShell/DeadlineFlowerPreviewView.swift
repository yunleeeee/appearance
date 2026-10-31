import SwiftUI

/// Shown only while a real DDL flower is hovered.
struct DeadlineFlowerDetailsView: View {
    let deadline: GardenDeadline
    let queuedCount: Int
    var stage: DeadlineStage? = nil
    var now: Date = Date()
    var onOpenSource: (() -> Void)? = nil

    private var remainingText: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate,
                             .withTime, .withColonSeparatorInTime]
        let stamp = deadline.dueDate + "T" + (deadline.dueTime ?? "")
        guard let date = iso.date(from: stamp) else { return "请核对截止时间" }
        let hours = abs(date.timeIntervalSince(now)) / 3600
        let quantity = hours >= 48 ? String(format: "%.0f 天", hours / 24)
            : String(format: "%.1f 小时", hours)
        return date <= now ? "已逾期 " + quantity : "剩余 " + quantity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(deadline.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Label(deadline.project, systemImage: "folder")
            Label(deadline.dueDate + (deadline.dueTime.map { " \($0)" } ?? " · 未注明时间"),
                  systemImage: "calendar")
            if deadline.yearInferred {
                Text("年份根据投喂日期推定").font(.caption).foregroundStyle(.secondary)
            }
            if let stage {
                Label("花期：\(stage.label)", systemImage: "leaf").font(.caption)
            }
            if deadline.yearInferred {
                Text("推断年份：请先核对日期").font(.caption).foregroundStyle(.orange)
            }
            if let time = deadline.dueTime {
                Text(remainingText).font(.caption).foregroundStyle(.secondary)
                Text("时间按本机时区解释：\(time)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("时间未注明，按日历日期显示，不触发小时级提醒")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let path = deadline.sourcePath {
                HStack {
                    Text("来源：" + URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption).lineLimit(1)
                    if onOpenSource != nil {
                        Button("查看来源") { onOpenSource?() }
                            .controlSize(.small)
                    }
                }
            }
            if !deadline.evidence.isEmpty {
                Text("证据：" + deadline.evidence).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(3)
            }
            Divider()
            Text("单击花朵并确认，才会标记完成；可在菜单撤销采摘").font(.caption)
            if queuedCount > 0 {
                Text("另有 \(queuedCount) 项 DDL 排队，收获后依次开花")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 285, alignment: .leading)
    }
}
