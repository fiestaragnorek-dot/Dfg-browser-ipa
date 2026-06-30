import SwiftUI

@main
struct DfgBrowserApp: App {
    @StateObject private var browserState = BrowserState()
    @StateObject private var extensionManager = ExtensionManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(browserState)
                .environmentObject(extensionManager)
                .preferredColorScheme(.light)
                .accentColor(.black)
        }
    }
}

// MARK: - Global Browser State
class BrowserState: ObservableObject {
    @Published var tabs: [BrowserTab] = [BrowserTab(url: URL(string: "dfg://newtab")!)]
    @Published var currentTabIndex: Int = 0
    @Published var isIncognito: Bool = false
    
    var currentTab: BrowserTab {
        get { tabs[currentTabIndex] }
        set { tabs[currentTabIndex] = newValue }
    }
    
    func newTab() {
        let tab = BrowserTab(url: URL(string: "dfg://newtab")!)
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
    }
    
    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if currentTabIndex >= tabs.count {
            currentTabIndex = tabs.count - 1
        }
    }
}

struct BrowserTab: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var title: String = "Новая вкладка"
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var progress: Double = 0.0
}
