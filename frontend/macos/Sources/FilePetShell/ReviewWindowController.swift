import AppKit
import SwiftUI

/// One editable review window for both uncertain DDLs and unclassified files.
@MainActor
final class ReviewWindowController: NSWindowController {
    init(store: ShellStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "待确认事项"
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FilePetPendingReviews")
        window.contentView = NSHostingView(rootView:
            PendingReviewView(store: store, inbox: store.reviewInbox))
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum ReviewMode: String, Hashable {
    case deadline, category
}

@MainActor
private struct PendingReviewView: View {
    @ObservedObject var store: ShellStore
    @ObservedObject var inbox: FileReviewInbox
    @State private var selectedReviewID: String?
    @State private var selectedCandidateID: String?
    @State private var mode: ReviewMode = .deadline
    @State private var title = ""
    @State private var project = ""
    @State private var dueDate = ""
    @State private var dueTime = ""
    @State private var categoryID = ""
    @State private var actionError: String?

    private var selectedReview: PendingFileReview? {
        inbox.items.first { $0.id == selectedReviewID }
    }

    private var selectedCandidate: EngineDeadline? {
        selectedReview?.candidates.first { $0.id == selectedCandidateID }
    }

    private var categoryIDs: [String] {
        store.categoryLabels.keys.sorted {
            let left = store.categoryLabels[$0] ?? $0
            let right = store.categoryLabels[$1] ?? $1
            return left == right ? $0 < $1 : left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private var optionalTime: String? {
        let value = dueTime.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var validationError: String? {
        DeadlineInput.validationError(title: title, project: project,
                                      dueDate: dueDate, dueTime: optionalTime)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("待确认文件")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                Text("\(inbox.items.count) 个文件")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
                List(selection: $selectedReviewID) {
                    ForEach(inbox.items) { review in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(review.fileName).lineLimit(2)
                            Text(review.candidates.isEmpty
                                 ? "补充 DDL 或指定分类"
                                 : "\(review.candidates.count) 项 DDL 待核对")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(review.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 225)
            Divider()
            if let review = selectedReview {
                reviewForm(review)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("暂无待确认事项").font(.title3)
                    Text("需要核对的 DDL 和分类会显示在这里。\n确认 DDL 后会生成花朵，多余的会依次排队。")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { reconcileSelection() }
        .onChange(of: selectedReviewID) { _ in loadSelectedReview() }
        .onChange(of: selectedCandidateID) { _ in loadSelectedCandidate() }
        .onChange(of: inbox.items) { _ in reconcileSelection() }
    }

    private func reviewForm(_ review: PendingFileReview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(review.fileName).font(.title3).fontWeight(.semibold)
                            Text(review.reason).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button("打开原文件") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: review.path))
                        }
                    }
                    Picker("处理方式", selection: $mode) {
                        Text("确认为 DDL").tag(ReviewMode.deadline)
                        Text("普通分类").tag(ReviewMode.category)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("review-mode")

                    if mode == .deadline {
                        deadlineFields(review)
                    } else {
                        categoryFields
                    }
                    if let actionError {
                        Text(actionError).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("忽略此文件") {
                    store.dismissReview(id: review.id)
                    actionError = nil
                    reconcileSelection()
                }
                .disabled(store.isBusy)
                Spacer()
                if mode == .deadline {
                    Button("确认 DDL 并生成花朵") { confirmDeadline(review) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(store.isBusy || validationError != nil)
                        .accessibilityIdentifier("confirm-deadline")
                } else {
                    Button("确认分类并增加葡萄") {
                        actionError = store.confirmCategory(reviewID: review.id, categoryID: categoryID)
                        if actionError == nil { reconcileSelection() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isBusy || !categoryIDs.contains(categoryID))
                    .accessibilityIdentifier("confirm-category")
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deadlineFields(_ review: PendingFileReview) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if review.candidates.count > 1 {
                Picker("候选 DDL", selection: $selectedCandidateID) {
                    ForEach(Array(review.candidates.enumerated()), id: \.element.id) { index, candidate in
                        Text("第 \(index + 1) 项 · \(candidate.dueDate)")
                            .tag(Optional(candidate.id))
                    }
                }
                .accessibilityIdentifier("review-candidate")
            }
            Text(review.candidates.isEmpty
                 ? "没有识别到明确截止日期。可以手动填写 DDL，或切换到普通分类。"
                 : "请按原文核对内容、日期和项目，确认后生成花朵。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("主要内容").font(.callout)
                TextEditor(text: $title)
                    .font(.body)
                    .frame(minHeight: 64, maxHeight: 90)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
                    .accessibilityLabel("主要内容")
                    .accessibilityIdentifier("review-title")
            }
            labelledField("项目", placeholder: "如软件工程、星河项目", text: $project, id: "review-project")
            HStack(alignment: .top, spacing: 14) {
                labelledField("截止日期", placeholder: "YYYY-MM-DD", text: $dueDate, id: "review-date")
                labelledField("截止时间（可选）", placeholder: "HH:mm，可留空", text: $dueTime, id: "review-time")
            }
            if selectedCandidate?.yearInferred == true {
                Text("年份由系统推定，请按原文核对。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let evidence = selectedCandidate?.evidence, !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("识别原文").font(.caption).foregroundStyle(.secondary)
                    Text(evidence).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var categoryFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请选择这个文件所属的分类。确认后，该类别新增一颗葡萄。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("分类", selection: $categoryID) {
                Text("请选择分类").tag("")
                ForEach(categoryIDs, id: \.self) { id in
                    Text(store.categoryLabels[id] ?? id).tag(id)
                }
            }
            .accessibilityIdentifier("review-category")
            if categoryIDs.isEmpty {
                Text("分类列表尚未就绪，请先连接分类核心。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func labelledField(_ label: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.callout)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private func confirmDeadline(_ review: PendingFileReview) {
        actionError = store.confirmDeadline(reviewID: review.id,
            candidateID: selectedCandidateID, title: title, project: project,
            dueDate: dueDate, dueTime: optionalTime)
        if actionError == nil { reconcileSelection() }
    }

    private func reconcileSelection() {
        guard let review = selectedReview else {
            selectedReviewID = inbox.items.first?.id
            if selectedReviewID == nil { actionError = nil }
            return
        }
        if let candidateID = selectedCandidateID {
            if !review.candidates.contains(where: { $0.id == candidateID }) { loadSelectedReview() }
        } else if !review.candidates.isEmpty {
            loadSelectedReview()
        }
    }

    private func loadSelectedReview() {
        actionError = nil
        mode = .deadline
        categoryID = ""
        selectedCandidateID = selectedReview?.candidates.first?.id
        loadSelectedCandidate()
    }

    private func loadSelectedCandidate() {
        actionError = nil
        if let candidate = selectedCandidate {
            title = candidate.title
            project = candidate.project
            dueDate = candidate.dueDate
            dueTime = candidate.dueTime ?? ""
        } else if let review = selectedReview {
            let name = URL(fileURLWithPath: review.fileName).deletingPathExtension().lastPathComponent
            title = name
            project = name
            dueDate = ""
            dueTime = ""
        }
    }
}
