import AppIntents
import SwiftUI
import WidgetKit

// ホーム画面・StandBy の照明ウィジェット。4ボタンをそのまま押せる（インタラクティブウィジェット）。
struct LightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LightWidget", provider: RemoteProvider(fetchSchedule: false)) { entry in
            LightWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("照明")
        .description("天井照明を全灯・ECO・常夜灯・消灯の4ボタンで操作します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RemoteEntry

    var body: some View {
        if !entry.configured {
            NotConfiguredView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "照明", systemImage: "lightbulb")
                if family == .systemSmall {
                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                        GridRow {
                            button(.on)
                            button(.eco)
                        }
                        GridRow {
                            button(.mame)
                            button(.off)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(LightButton.allCases) { button($0) }
                    }
                    ResultLine(result: entry.lastResult)
                }
            }
        }
    }

    private func button(_ b: LightButton) -> some View {
        Button(intent: LightIntent(button: b)) {
            VStack(spacing: 2) {
                Image(systemName: b.systemImage).font(.title3)
                Text(b.label).font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
