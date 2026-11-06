import AppIntents
import SwiftUI
import WidgetKit

// ロック画面（と StandBy）の1ボタンウィジェット。長押しの「ウィジェットを編集」で操作を選ぶ。
struct QuickActionConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "操作を選ぶ"
    static var description = IntentDescription("ウィジェットを押したときに送る操作を選びます。")

    @Parameter(title: "操作", default: .lightOn)
    var action: QuickAction
}

struct QuickActionEntry: TimelineEntry {
    let date: Date
    let action: QuickAction
}

struct QuickActionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickActionEntry {
        QuickActionEntry(date: .now, action: .lightOn)
    }

    func snapshot(for configuration: QuickActionConfigIntent, in context: Context) async -> QuickActionEntry {
        QuickActionEntry(date: .now, action: configuration.action)
    }

    func timeline(for configuration: QuickActionConfigIntent, in context: Context) async -> Timeline<QuickActionEntry> {
        Timeline(entries: [QuickActionEntry(date: .now, action: configuration.action)], policy: .never)
    }
}

struct QuickActionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuickActionWidget", intent: QuickActionConfigIntent.self, provider: QuickActionProvider()) {
            entry in
            QuickActionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ワンタップ操作")
        .description("照明やエアコンの操作を1つ選んで、押すだけで送ります。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct QuickActionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickActionEntry

    var body: some View {
        Button(intent: QuickActionIntent(action: entry.action)) {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: entry.action.systemImage).font(.title2)
                }
            case .accessoryRectangular:
                Label(entry.action.label, systemImage: entry.action.systemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(spacing: 8) {
                    Image(systemName: entry.action.systemImage).font(.largeTitle)
                    Text(entry.action.label).font(.caption.bold())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .widgetAccentable()
    }
}
