import SwiftUI
import WidgetKit

/// A Pro widget placed without Pro: tapping it opens the app, where Pro can be turned on.
struct ProLockedWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill").font(.title3)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Pro 위젯", systemImage: "lock.fill").font(.headline)
                Text("세트 카운터 Pro에서 쓸 수 있어요").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                Spacer(minLength: 0)
                Text("세트 카운터 Pro").font(.headline)
                Text("이 위젯은 Pro에서 쓸 수 있어요. 눌러서 앱을 열어 보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
