import SwiftUI
import TrueFocusKit

struct RootView: View {
    @Environment(FocusController.self) private var controller

    var body: some View {
        @Bindable var controller = controller

        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    TodayView()
                }
            }
            Tab("Notes", systemImage: "note.text") {
                NotesHomeView()
            }
            Tab("Guard", systemImage: "shield.lefthalf.filled") {
                NavigationStack {
                    GuardView()
                }
            }
        }
        .tint(TF.Palette.signal)
        .fullScreenCover(isPresented: $controller.isFocusScreenPresented) {
            FocusScreen()
                .environment(controller)
        }
    }
}
