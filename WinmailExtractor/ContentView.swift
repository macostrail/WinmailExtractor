import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false

    private let tnefType = UTType(importedAs: "com.microsoft.tnef", conformingTo: .data)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            dropArea

            if !model.records.isEmpty {
                Divider().padding(.horizontal, 28)
                history
            }
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 430, idealHeight: 510)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.045)],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .shadow(color: Color.accentColor.opacity(0.2), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Winmail Extractor")
                    .font(.title2.weight(.semibold))
                Text("winmail.dat の添付ファイルをかんたんに取り出します")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var dropArea: some View {
        VStack(spacing: 18) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "doc.badge.gearshape")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)

            VStack(spacing: 6) {
                Text("ここに winmail.dat をドロップ")
                    .font(.headline)
                Text("またはFinderからファイルを選択してください")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("winmail.datを選ぶ…") {
                model.chooseFiles()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isProcessing)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.23),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7])
                        )
                }
        )
        .padding(28)
        .dropDestination(for: URL.self) { urls, _ in
            let candidates = urls.filter { $0.pathExtension.lowercased() == "dat" }
            guard !candidates.isEmpty else { return false }
            model.open(candidates)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近の処理")
                .font(.headline)

            ForEach(model.records.prefix(3)) { record in
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: record.outcome))
                        .foregroundStyle(iconColor(for: record.outcome))
                        .frame(width: 18)
                    Text(record.sourceName)
                        .lineLimit(1)
                    Spacer()
                    Text(summary(for: record.outcome))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private func iconName(for outcome: ExtractionRecord.Outcome) -> String {
        switch outcome {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    private func iconColor(for outcome: ExtractionRecord.Outcome) -> Color {
        switch outcome {
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .secondary
        }
    }

    private func summary(for outcome: ExtractionRecord.Outcome) -> String {
        switch outcome {
        case let .success(count, destination):
            return "\(count)個 → \(destination.lastPathComponent)"
        case let .failure(message):
            return message
        case .cancelled:
            return "キャンセル"
        }
    }
}
