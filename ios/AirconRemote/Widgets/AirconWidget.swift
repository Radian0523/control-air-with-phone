import AppIntents
import SwiftUI
import WidgetKit

// ホーム画面・StandBy のエアコンウィジェット。前回の設定で運転 / 停止、予約の表示、おやすみタイマー。
struct AirconWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AirconWidget", provider: RemoteProvider(fetchSchedule: true)) { entry in
            AirconWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("エアコン")
        .description("前回の設定での運転・停止と、予約の確認ができます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AirconWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemoteEntry

    private var settingForOn: Setting {
        var s = entry.setting
        s.power = true
        return s
    }

    var body: some View {
        if !entry.configured {
            NotConfiguredView()
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "エアコン", systemImage: "fan")
                Text(Setting.summary(settingForOn))
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                scheduleLine
                HStack(spacing: 6) {
                    onButton
                    offButton
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "エアコン", systemImage: "fan")
                    Text(Setting.summary(settingForOn))
                        .font(.subheadline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    scheduleLine
                    ResultLine(result: entry.lastResult)
                }
                VStack(spacing: 6) {
                    onButton
                    offButton
                    Button(intent: SleepTimerIntent(minutes: 60)) {
                        Label("60分後に停止", systemImage: "moon.zzz")
                            .font(.caption)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 130)
            }
        }
    }

    private var onButton: some View {
        Button(intent: AirconOnIntent()) {
            Label("運転", systemImage: "power")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var offButton: some View {
        Button(intent: AirconOffIntent()) {
            Label("停止", systemImage: "stop.circle")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var scheduleLine: some View {
        Group {
            if let record = entry.schedule, let at = ExecuteAtFormat.date(from: record.executeAt) {
                Label("\(at.formatted(date: .omitted, time: .shortened)) \(record.setting.power ? "運転" : "停止")", systemImage: "clock")
            } else if entry.scheduleUnknown {
                Label("予約を取得できません", systemImage: "clock.badge.questionmark")
            } else {
                Label("予約なし", systemImage: "clock")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
