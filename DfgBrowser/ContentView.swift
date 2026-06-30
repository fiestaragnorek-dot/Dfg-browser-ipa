import SwiftUI

struct ContentView: View {
    @EnvironmentObject var browserState: BrowserState
    @EnvironmentObject var extensionManager: ExtensionManager
    @State private var showExtensions = false
    @State private var showSettings = false
    @State private var showTabs = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top monochrome toolbar
                TopBar(
                    showExtensions: $showExtensions,
                    showSettings: $showSettings,
                    showTabs: $showTabs
                )
                
                Divider().background(Color.black)
                
                // Web content
                BrowserView(tab: $browserState.currentTab)
                    .environmentObject(extensionManager)
                
                Divider().background(Color.black.opacity(0.2))
                
                // Bottom toolbar - black & white
                BottomBar(
                    showExtensions: $showExtensions,
                    showTabs: $showTabs
                )
            }
        }
        .sheet(isPresented: $showExtensions) {
            ChromeStoreViewV2()
                .environmentObject(extensionManager)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTabs) {
            TabsGridView()
                .environmentObject(browserState)
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var browserState: BrowserState
    @Binding var showExtensions: Bool
    @Binding var showSettings: Bool
    @Binding var showTabs: Bool
    
    @State private var addressText: String = ""
    @FocusState private var isAddressFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // URL Bar
            HStack(spacing: 10) {
                Button(action: {
                    // back handled in webview
                    NotificationCenter.default.post(name: .browserGoBack, object: nil)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(browserState.currentTab.canGoBack ? .black : .gray)
                }
                .disabled(!browserState.currentTab.canGoBack)
                
                Button(action: {
                    NotificationCenter.default.post(name: .browserGoForward, object: nil)
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(browserState.currentTab.canGoForward ? .black : .gray)
                }
                .disabled(!browserState.currentTab.canGoForward)
                
                // Address field - monochrome
                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundColor(.black.opacity(0.5))
                    
                    TextField("Поиск или адрес", text: $addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.black)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isAddressFocused)
                        .onSubmit { navigate() }
                    
                    if browserState.currentTab.isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.black)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 1.5)
                        .background(Color.white)
                )
                
                Button(action: {
                    if browserState.currentTab.isLoading {
                        NotificationCenter.default.post(name: .browserStop, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .browserReload, object: nil)
                    }
                }) {
                    Image(systemName: browserState.currentTab.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
            
            // Progress
            if browserState.currentTab.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: geo.size.width * browserState.currentTab.progress, height: 2)
                        .animation(.linear(duration: 0.15), value: browserState.currentTab.progress)
                }
                .frame(height: 2)
            }
        }
        .onChange(of: browserState.currentTab.url) { newUrl in
            if !isAddressFocused {
                addressText = newUrl.absoluteString == "dfg://newtab" ? "" : newUrl.absoluteString
            }
        }
        .onAppear {
            addressText = browserState.currentTab.url.absoluteString == "dfg://newtab" ? "" : browserState.currentTab.url.absoluteString
        }
    }
    
    private func navigate() {
        var text = addressText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return }
        var urlString = text
        if !text.contains("://") && !text.contains(" ") {
            if text.contains(".") {
                urlString = "https://" + text
            } else {
                let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                urlString = "https://www.google.com/search?q=\(query)"
            }
        } else if text.contains(" ") {
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlString = "https://www.google.com/search?q=\(query)"
        }
        if let url = URL(string: urlString) {
            browserState.currentTab.url = url
            isAddressFocused = false
        }
    }
}

struct BottomBar: View {
    @EnvironmentObject var browserState: BrowserState
    @EnvironmentObject var extensionManager: ExtensionManager
    @Binding var showExtensions: Bool
    @Binding var showTabs: Bool
    
    var body: some View {
        HStack {
            Button {
                showExtensions = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 18))
                    Text("\(extensionManager.enabledExtensions.count)")
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .foregroundColor(.black)
            
            Spacer()
            
            Text("Dfg Browser")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(.black)
            
            Spacer()
            
            Button {
                showTabs = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 17))
                    Text("\(browserState.tabs.count)")
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            .foregroundColor(.black)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// Notifications
extension Notification.Name {
    static let browserGoBack = Notification.Name("browserGoBack")
    static let browserGoForward = Notification.Name("browserGoForward")
    static let browserReload = Notification.Name("browserReload")
    static let browserStop = Notification.Name("browserStop")
}
