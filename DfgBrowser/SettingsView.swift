import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("searchEngine") private var searchEngine = "Google"
    @AppStorage("doNotTrack") private var doNotTrack = true
    @AppStorage("blockAds") private var blockAds = true
    @AppStorage("userAgentDesktop") private var userAgentDesktop = true
    
    let engines = ["Google", "DuckDuckGo", "Yandex", "Bing"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ОСНОВНОЕ").font(.system(size: 11, design: .monospaced))) {
                    Picker("Поиск", selection: $searchEngine) {
                        ForEach(engines, id: \.self) { Text($0) }
                    }
                    Toggle("Desktop User-Agent", isOn: $userAgentDesktop)
                    Toggle("Do Not Track", isOn: $doNotTrack)
                }
                
                Section(header: Text("КОНФИДЕНЦИАЛЬНОСТЬ").font(.system(size: 11, design: .monospaced))) {
                    Toggle("Блокировка рекламы (uBlock)", isOn: $blockAds)
                    Button("Очистить данные") {}
                        .foregroundColor(.black)
                    Button("Очистить cookies") {}
                        .foregroundColor(.black)
                }
                
                Section(header: Text("DFG BROWSER").font(.system(size: 11, design: .monospaced))) {
                    HStack { Text("Версия"); Spacer(); Text("1.0.3").font(.system(.body, design: .monospaced)).foregroundColor(.gray) }
                    HStack { Text("Движок"); Spacer(); Text("WebKit / CRX").font(.system(.body, design: .monospaced)).foregroundColor(.gray) }
                    HStack { Text("Расширения"); Spacer(); Text("Chrome Store ✓").font(.system(.body, design: .monospaced)).foregroundColor(.gray) }
                }
                
                Section(footer: Text("Dfg Browser • Monochrome Edition\nСделано в стиле Lemur Browser. Поддержка Chrome Extensions Store.").font(.system(size: 11, design: .monospaced)).multilineTextAlignment(.center).frame(maxWidth: .infinity)) {
                    EmptyView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
        .accentColor(.black)
    }
}

struct TabsGridView: View {
    @EnvironmentObject var browserState: BrowserState
    @Environment(\.dismiss) var dismiss
    
    let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(browserState.tabs.enumerated()), id: \.element.id) { index, tab in
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(browserState.currentTabIndex == index ? Color.black : Color.black.opacity(0.3), lineWidth: browserState.currentTabIndex == index ? 2 : 1)
                                    .background(Color.white)
                                    .frame(height: 130)
                                VStack {
                                    Text(tab.title)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(8)
                                    Text(tab.url.host ?? "new tab")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                            HStack {
                                Text("Вкладка \(index+1)")
                                    .font(.system(size: 10, design: .monospaced))
                                Spacer()
                                Button {
                                    browserState.closeTab(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundColor(.black.opacity(0.6))
                            .padding(.top, 6)
                        }
                        .onTapGesture {
                            browserState.currentTabIndex = index
                            dismiss()
                        }
                    }
                    
                    // New tab card
                    Button {
                        browserState.newTab()
                        dismiss()
                    } label: {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                            .foregroundColor(.black.opacity(0.4))
                            .frame(height: 130)
                            .overlay(
                                VStack {
                                    Image(systemName: "plus")
                                        .font(.title2)
                                    Text("Новая")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .foregroundColor(.black.opacity(0.6))
                            )
                    }
                }
                .padding()
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Вкладки • \(browserState.tabs.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
    }
}
