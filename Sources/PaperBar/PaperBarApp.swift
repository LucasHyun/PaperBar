import AppKit
import SwiftUI

@main
struct PaperBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PaperStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(count: store.unseenCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 메뉴바 아이콘. 안 본 새 논문이 있으면 개수를 같이 표시.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(Image(systemName: "newspaper.fill")) \(count > 99 ? "99+" : String(count))")
        } else {
            Image(systemName: "newspaper")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` 으로 띄워도 Dock 아이콘 없이 메뉴바에만 보이게
        NSApp.setActivationPolicy(.accessory)
    }
}
