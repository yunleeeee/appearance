import SwiftUI

/// Shown only while a real DDL flower is hovered.
struct DeadlineFlowerDetailsView: View {
    let deadline: GardenDeadline
    let queuedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(deadline.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Label(deadline.project, systemImage: "folder")
            Label(deadline.dueDate + (deadline.dueTime.map { " \($0)" } ?? " · 未注明时间"),
                  systemImage: "calendar")
            if deadline.yearInferred {
                Text("年份根据投喂日期推定").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("点击花朵收获，完成这项 DDL").font(.caption)
            if queuedCount > 0 {
                Text("另有 \(queuedCount) 项 DDL 排队，收获后依次开花")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 285, alignment: .leading)
    }
}
