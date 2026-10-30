import ActivityCore
import Charts
import SwiftUI

enum MetricKind {
    case cpu, memory, storage, network

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .storage: "Storage"
        case .network: "Network"
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .network: "network"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: .orange
        case .memory: .purple
        case .storage: .blue
        case .network: .green
        }
    }

    var chartUnit: String {
        switch self {
        case .cpu, .storage: "%"
        case .memory: "GB"
        case .network: "MB/s"
        }
    }
}

private struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    let series: String
    var id: String { "\(series)-\(date.timeIntervalSince1970)" }
}

struct MetricDetailView: View {
    let kind: MetricKind
    @ObservedObject var store: NearbyMacStore
    let preview: MetricSnapshot

    private var latest: MetricSnapshot { store.snapshot ?? preview }
    private var isPreview: Bool { store.selectedName == nil }
    private var isAwaitingReading: Bool { !isPreview && store.snapshot == nil }

    private var points: [ChartPoint] {
        store.history.flatMap { sample -> [ChartPoint] in
            switch kind {
            case .cpu:
                return sample.cpuFraction.map { [ChartPoint(date: sample.timestamp, value: $0 * 100, series: "CPU")] } ?? []
            case .memory:
                return sample.memoryUsedBytes.map {
                    [ChartPoint(date: sample.timestamp, value: Double($0) / 1_000_000_000, series: "Memory")]
                } ?? []
            case .storage:
                guard let free = sample.diskFreeBytes, let total = sample.diskTotalBytes, total > 0 else { return [] }
                return [ChartPoint(date: sample.timestamp, value: (1 - Double(free) / Double(total)) * 100, series: "Used")]
            case .network:
                var result: [ChartPoint] = []
                if let down = sample.networkReceivedBytesPerSecond {
                    result.append(ChartPoint(date: sample.timestamp, value: down / 1_000_000, series: "Download"))
                }
                if let up = sample.networkSentBytesPerSecond {
                    result.append(ChartPoint(date: sample.timestamp, value: up / 1_000_000, series: "Upload"))
                }
                return result
            }
        }
    }

    private var axisMaximum: Double {
        switch kind {
        case .cpu, .storage: 100
        case .memory: max(1, Double(latest.memoryTotalBytes ?? 0) / 1_000_000_000,
                          (points.map(\.value).max() ?? 0) * 1.1)
        case .network: max(0.1, (points.map(\.value).max() ?? 0) * 1.2)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(kind.tint)
                            .frame(width: 36, height: 36)
                            .background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                            Text(isPreview ? "Sample values" : store.selectedName ?? "Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(primaryValue)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text(secondaryValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .statsCardBackground()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Recent activity")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text(kind.chartUnit).font(.caption).foregroundStyle(.secondary)
                    }
                    if Set(points.map(\.date)).count >= 2 {
                        Chart(points) { point in
                            LineMark(
                                x: .value("Time", point.date),
                                y: .value(kind.chartUnit, point.value),
                                series: .value("Metric", point.series)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(point.series == "Upload" ? Color.teal : kind.tint)
                        }
                        .chartYScale(domain: 0...axisMaximum)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine()
                                AxisValueLabel(format: .dateTime.hour().minute())
                            }
                        }
                        .chartLegend(.hidden)
                        .frame(height: 220)
                        .accessibilityLabel("\(kind.title) readings from the last 30 minutes")
                        if kind == .network {
                            HStack(spacing: 18) {
                                chartKey("Download", color: kind.tint)
                                chartKey("Upload", color: .teal)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            isPreview ? "Pair a Mac to see history" : "Waiting for readings",
                            systemImage: "chart.xyaxis.line",
                            description: Text(isPreview
                                              ? "History appears after you connect to a Mac."
                                              : "The graph appears after two readings arrive from your Mac.")
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .statsCardBackground()

                VStack(spacing: 12) {
                    switch kind {
                    case .cpu:
                        row("Processor load", MetricFormat.percent(latest.cpuFraction))
                    case .memory:
                        row("Used", MetricFormat.bytes(latest.memoryUsedBytes))
                        row("Physical memory", MetricFormat.bytes(latest.memoryTotalBytes))
                    case .storage:
                        row("Free", MetricFormat.bytes(latest.diskFreeBytes))
                        row("Startup volume capacity", MetricFormat.bytes(latest.diskTotalBytes))
                    case .network:
                        row("Download", MetricFormat.rate(latest.networkReceivedBytesPerSecond))
                        row("Upload", MetricFormat.rate(latest.networkSentBytesPerSecond))
                    }
                    Divider()
                    if isPreview {
                        row("Data source", "Sample values")
                    } else if let reading = store.snapshot?.timestamp {
                        row("Last reading", reading.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        row("Last reading", "Waiting for Mac")
                    }
                }
                .padding(20)
                .statsCardBackground()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var primaryValue: String {
        switch kind {
        case .cpu: MetricFormat.percent(latest.cpuFraction)
        case .memory: MetricFormat.bytes(latest.memoryUsedBytes)
        case .storage: MetricFormat.bytes(latest.diskFreeBytes)
        case .network: MetricFormat.rate(latest.networkReceivedBytesPerSecond)
        }
    }

    private var secondaryValue: String {
        if isAwaitingReading { return "Waiting for your Mac to send readings" }
        return switch kind {
        case .cpu: "Total processor usage"
        case .memory: "Memory currently in use"
        case .storage: "Free on the startup volume"
        case .network: "Download rate · upload \(MetricFormat.rate(latest.networkSentBytesPerSecond))"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func chartKey(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
