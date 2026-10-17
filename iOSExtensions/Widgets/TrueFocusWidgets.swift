import SwiftUI
import WidgetKit

/// Everything the TrueFocus widget extension provides.
@main
struct TrueFocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowWidget()
        FocusLiveActivity()
        DoneControl()
        NextTaskControl()
    }
}
