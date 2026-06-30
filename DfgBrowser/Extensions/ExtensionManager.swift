import Foundation
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - Extension model - Chrome compatible
struct InstalledExtension: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var version: String
    var description: String
    var enabled: Bool = true
    var contentScripts: [String] = [] // injected JS
    var manifest: [String: String] = [:]
    var iconBase64: String? = nil
    var permissions: [String] = []
    var storeUrl: String? = nil
}

// Tampermonkey core – built-in userscript manager for Dfg
enum TampermonkeyCore {
    static let loaderScript = """
// == Dfg Tampermonkey Core v5.3 ==
console.log('[Dfg] Tampermonkey active');
(function(){
if(window.__TM_DFG__)return; window.__TM_DFG__=true;

// GM API stub
window.GM_info={scriptHandler:"Tampermonkey",version:"5.3-dfg",script:{name:"Dfg Userscript"}};
window.GM_getValue=(k,d)=>{try{return JSON.parse(localStorage.getItem('TM_'+k)??'null')??d}catch{return d}};
window.GM_setValue=(k,v)=>localStorage.setItem('TM_'+k,JSON.stringify(v));
window.GM_deleteValue=k=>localStorage.removeItem('TM_'+k);
window.GM_xmlhttpRequest=({method='GET',url,onload})=>fetch(url,{method}).then(r=>r.text()).then(t=>onload&&onload({responseText:t,status:200}));
window.GM_addStyle=css=>{const s=document.createElement('style');s.textContent=css;document.head.appendChild(s);return s};
window.GM_log=console.log.bind(console);
window.unsafeWindow=window;

// userscript storage
const KEY='dfg_tm_scripts_v1';
function getScripts(){ try{return JSON.parse(localStorage.getItem(KEY)||'[]')}catch{return[]} }
function saveScripts(a){ localStorage.setItem(KEY, JSON.stringify(a)) }
window.TM_getScripts=getScripts;
window.TM_addScript = function(meta, code){
  const arr=getScripts(); arr.push({id:Date.now().toString(36), meta, code, enabled:true, time:Date.now()}); saveScripts(arr); console.log('[TM] script added', meta); location.reload();
};
window.TM_toggle = function(id){ const s=getScripts(); const f=s.find(x=>x.id===id); if(f){f.enabled=!f.enabled;saveScripts(s);location.reload()} };

// run matching scripts
function match(url, pattern){
  try{
    const re = new RegExp('^' + pattern.replace(/[.+?^${}()|[\\]\\\\]/g,'\\\\$&').replace(/\\*/g,'.*') + '$');
    return re.test(url);
  }catch{return url.includes(pattern.replace(/\\*/g,''))}
}
const scripts = getScripts().filter(s=>s.enabled);
const href = location.href;
scripts.forEach(us=>{
  try{
    const meta = us.meta||'';
    const matches = [...meta.matchAll(/@match\\s+([^\\n]+)/g)].map(m=>m[1].trim());
    const includes = [...meta.matchAll(/@include\\s+([^\\n]+)/g)].map(m=>m[1].trim());
    const patterns = [...matches, ...includes];
    if(patterns.length===0 || patterns.some(p=>match(href,p))){
      console.log('[TM] running', us.meta.split('\\n')[0]);
      (new Function(us.code))();
    }
  }catch(e){ console.error('[TM] error',e)}
});

// UI – long press top-left 1s to open manager
let pressTimer;
document.addEventListener('touchstart',e=>{ if(e.touches[0].clientX<60 && e.touches[0].clientY<60){ pressTimer=setTimeout(openTM,900)}},{passive:true});
document.addEventListener('touchend',()=>clearTimeout(pressTimer));
document.addEventListener('mousedown',e=>{ if(e.clientX<60&&e.clientY<60) pressTimer=setTimeout(openTM,900)});
document.addEventListener('mouseup',()=>clearTimeout(pressTimer));

function openTM(){
  const scripts=getScripts();
  const list = scripts.map((s,i)=>`${i+1}. ${(s.meta.match(/@name\\s+([^\n]+)/)||[])[1]||'Unnamed'} [${s.enabled?'ON':'OFF'}] id:${s.id}`).join('\\n') || '(пусто)';
  const cmd = prompt('TAMPERMONKEY DFG\\n\\nУстановлено: '+scripts.length+'\\n\\n'+list+'\\n\\nКоманды:\\nnew – добавить скрипт\\ntoggle <id> – вкл/выкл\\ndel <id> – удалить\\nexport – экспорт\\n\\nДолгое нажатие в левом верхнем углу открывает это меню', 'new');
  if(!cmd) return;
  if(cmd==='new'){
    const meta = prompt('Вставь ==UserScript== meta блок:\\n// ==UserScript==\\n// @name My Script\\n// @match *://*/*\\n// ==/UserScript==', '// ==UserScript==\\n// @name New Script\\n// @match *://*/*\\n// ==/UserScript==');
    if(!meta) return;
    const code = prompt('Код скрипта (JS):', "console.log('Hello from TM'); alert('Tampermonkey Dfg работает!');");
    if(code===null) return;
    TM_addScript(meta, code);
  } else if(cmd.startsWith('toggle ')){
    TM_toggle(cmd.split(' ')[1]);
  } else if(cmd.startsWith('del ')){
    const id=cmd.split(' ')[1]; saveScripts(getScripts().filter(x=>x.id!==id)); location.reload();
  } else if(cmd==='export'){
    prompt('Скопируй JSON:', JSON.stringify(getScripts()));
  }
}
window.openTampermonkey = openTM;
console.log('%c[Tampermonkey Dfg] Long-press top-left corner to open manager – or run openTampermonkey()', 'color:#000;background:#fff;border:1px solid #000;padding:2px 4px');
})();
"""
}

class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = [] {
        didSet { save() }
    }
    
    var enabledExtensions: [InstalledExtension] {
        installedExtensions.filter { $0.enabled }
    }
    
    private let storageKey = "dfg.installedExtensions.v1"
    
    init() {
        load()
        // Seed with example extensions like Lemur does
        if installedExtensions.isEmpty {
            installedExtensions = ExtensionManager.demoExtensions
        }
    }
    
    func toggle(_ ext: InstalledExtension) {
        if let idx = installedExtensions.firstIndex(of: ext) {
            installedExtensions[idx].enabled.toggle()
        }
    }
    
    func remove(_ ext: InstalledExtension) {
        installedExtensions.removeAll { $0.id == ext.id }
    }
    
    // Install from Chrome Web Store ID (Lemur-style)
    func installFromStore(storeId: String, name: String) async throws {
        // Chrome Web Store CRX download URL pattern
        // https://clients2.google.com/service/update2/crx?response=redirect&prodversion=126.0&acceptformat=crx2,crx3&x=id%3DSTOReID%26uc
        let crxUrlString = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=126.0&acceptformat=crx2,crx3&x=id%3D\(storeId)%26installsource%3Dondemand%26uc"
        guard let url = URL(string: crxUrlString) else { throw ExtensionError.badUrl }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ExtensionError.downloadFailed
        }
        
        try await installCRX(data: data, storeId: storeId, fallbackName: name)
    }
    
    func installCRX(data: Data, storeId: String, fallbackName: String) async throws {
        // Parse CRX header, unzip
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let crxPath = tempDir.appendingPathComponent("ext.crx")
        try data.write(to: crxPath)
        
        // CRX3 header strip
        let crxData = try Data(contentsOf: crxPath)
        var zipStart = 0
        if crxData.prefix(4) == Data("Cr24".utf8) {
            // Find ZIP start (PK)
            if let pkRange = crxData.range(of: Data([0x50, 0x4b, 0x03, 0x04])) {
                zipStart = pkRange.lowerBound
            }
        }
        let zipData = crxData.dropFirst(zipStart)
        let zipPath = tempDir.appendingPathComponent("ext.zip")
        try zipData.write(to: zipPath)
        
        let unzipDir = tempDir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipPath, to: unzipDir)
        
        // Read manifest.json
        let manifestUrl = unzipDir.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestUrl)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] ?? [:]
        
        let name = manifest["name"] as? String ?? fallbackName
        let version = manifest["version"] as? String ?? "1.0"
        let description = manifest["description"] as? String ?? ""
        
        // Collect content_scripts
        var scripts: [String] = []
        if let contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for cs in contentScripts {
                if let jsFiles = cs["js"] as? [String] {
                    for js in jsFiles {
                        let jsUrl = unzipDir.appendingPathComponent(js)
                        if let script = try? String(contentsOf: jsUrl, encoding: .utf8) {
                            scripts.append(script)
                        }
                    }
                }
            }
        }
        
        let ext = InstalledExtension(
            id: storeId,
            name: name,
            version: version,
            description: description,
            enabled: true,
            contentScripts: scripts,
            manifest: ["manifest_version": "\(manifest["manifest_version"] ?? 3)"],
            permissions: manifest["permissions"] as? [String] ?? [],
            storeUrl: "https://chromewebstore.google.com/detail/\(storeId)"
        )
        
        await MainActor.run {
            if let idx = installedExtensions.firstIndex(where: { $0.id == ext.id }) {
                installedExtensions[idx] = ext
            } else {
                installedExtensions.append(ext)
            }
        }
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // Manual .crx import
    func importCRX(url: URL) async throws {
        let data = try Data(contentsOf: url)
        let storeId = url.deletingPathExtension().lastPathComponent
        try await installCRX(data: data, storeId: storeId, fallbackName: storeId)
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(installedExtensions) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([InstalledExtension].self, from: data) {
            installedExtensions = decoded
        }
    }
    
    enum ExtensionError: LocalizedError {
        case badUrl, downloadFailed, parseFailed
        var errorDescription: String? {
            switch self {
            case .badUrl: return "Неверный URL расширения"
            case .downloadFailed: return "Не удалось скачать CRX"
            case .parseFailed: return "Не удалось распаковать расширение"
            }
        }
    }
    
    // Demo extensions - preinstalled like in Lemur
    static let demoExtensions: [InstalledExtension] = [
        InstalledExtension(
            id: "cjpalhdlnbpafiamejdnhcphjbkeiagm",
            name: "uBlock Origin",
            version: "1.58",
            description: "Эффективный блокировщик рекламы.",
            enabled: true,
            contentScripts: ["""
// Dfg uBlock lite
console.log('[Dfg] uBlock Origin active');
(function(){
  const blockList = ["doubleclick.net","googlesyndication","googleadservices","adservice.google","adsystem","/ads/","/ad_",".ads.","ads.","popunder","clickbait"];
  const origFetch = window.fetch;
  window.fetch = function(input, init){
    try { const url = (typeof input==='string'?input:input.url)||''; if(blockList.some(b=>url.includes(b))){ console.log('[uBlock] blocked',url); return Promise.reject(new TypeError('Blocked'));} } catch(e){}
    return origFetch.apply(this, arguments);
  };
  const obs = new MutationObserver(()=>{
    document.querySelectorAll('iframe[src*="ads"], div[id*="ad"], div[class*="ad-"], ins.adsbygoogle, [id^="google_ads"]').forEach(el=>el.remove());
  });
  obs.observe(document.documentElement,{childList:true,subtree:true});
})();
"""],
            permissions: ["<all_urls>", "webRequest", "storage"],
            storeUrl: "https://chromewebstore.google.com/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm"
        ),
        InstalledExtension(
            id: "mnojpmjdmbbfmejpflffifhffcmidifd",
            name: "Tampermonkey",
            version: "5.3",
            description: "Менеджер пользовательских скриптов. Установлен по умолчанию в Dfg Browser.",
            enabled: true,
            contentScripts: [TampermonkeyCore.loaderScript],
            permissions: ["<all_urls>", "storage", "activeTab", "scripting"],
            storeUrl: "https://chromewebstore.google.com/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo"
        ),
        InstalledExtension(
            id: "eimadpbcbfnmbkopoojfekhnkhdbieeh",
            name: "Dark Reader",
            version: "4.9",
            description: "Тёмный режим для всех сайтов",
            enabled: false,
            contentScripts: ["""
// Dark Reader lite for Dfg
if(!window.__darkReaderDfg){
window.__darkReaderDfg=true;
const s=document.createElement('style');
s.textContent=`html{filter:invert(1) hue-rotate(180deg) !important;background:#111 !important} img,video,iframe,canvas,svg,[style*="background-image"]{filter:invert(1) hue-rotate(180deg) !important}`;
function toggleDR(){ const e=document.getElementById('__dfg_dr'); if(e){e.remove()} else {s.id='__dfg_dr'; document.documentElement.appendChild(s)}}
if(localStorage.getItem('dfg_darkreader')==='1') toggleDR();
console.log('[Dfg] Dark Reader ready. window.toggleDarkReader()');
window.toggleDarkReader=()=>{ const on=!document.getElementById('__dfg_dr'); if(on){document.documentElement.appendChild(s);s.id='__dfg_dr';localStorage.setItem('dfg_darkreader','1')} else {document.getElementById('__dfg_dr')?.remove();localStorage.setItem('dfg_darkreader','0')}; return on; };
}
"""],
            permissions: ["<all_urls>"],
            storeUrl: "https://chromewebstore.google.com/detail/dark-reader/eimadpbcbfnmbkopoojfekhnkhdbieeh"
        ),
        InstalledExtension(
            id: "nngceckbapebfimnlniiiahkandclblb",
            name: "Bitwarden",
            version: "2024.6",
            description: "Менеджер паролей",
            enabled: false,
            contentScripts: [],
            permissions: ["storage", "activeTab"],
            storeUrl: "https://chromewebstore.google.com/detail/bitwarden-free-password-m/nngceckbapebfimnlniiiahkandclblb"
        ),
        InstalledExtension(
            id: "bfnaelmomeimhlpmgjnjophhpkkoljpa",
            name: "Violentmonkey",
            version: "2.18",
            description: "Open-source менеджер скриптов",
            enabled: false,
            contentScripts: [TampermonkeyCore.loaderScript],
            permissions: ["<all_urls>", "storage"],
            storeUrl: "https://chromewebstore.google.com/detail/violentmonkey/jinjaccalgkegednnccohejagnlnfdag"
        )
    ]
}

// MARK: - Chrome Web Store View
struct ChromeStoreView: View {
    @EnvironmentObject var extensionManager: ExtensionManager
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    @State private var isInstalling = false
    @State private var installStatus = ""
    
    // Popular extensions catalog (like Lemur quick-install)
    let featured: [(id: String, name: String, desc: String)] = [
        ("cjpalhdlnbpafiamejdnhcphjbkeiagm", "uBlock Origin", "Блокировка рекламы"),
        ("gighmmpiobklfepjocnamgkkbiglidom", "AdBlock", "Классический AdBlock"),
        ("nngceckbapebfimnlniiiahkandclblb", "Bitwarden", "Менеджер паролей"),
        ("eimadpbcbfnmbkopoojfekhnkhdbieeh", "Dark Reader", "Тёмный режим для всех сайтов"),
        ("hdokiejnpimakedhajhdlcegeplioahd", "LastPass", "LastPass менеджер"),
        ("mnojpmjdmbbfmejpflffifhffcmidifd", "Tampermonkey", "Пользовательские скрипты"),
        ("bfnaelmomeimhlpmgjnjophhpkkoljpa", "Violentmonkey", "Скрипты, open-source"),
        ("fihnjjcciajhdojfnbdddfaoknhalnja", "I don't care about cookies", "Убирает cookie-баннеры"),
        ("jpkfjicglakibpnggojglcpgnigdbajp", "SingleFile", "Сохранить страницу одним файлом"),
        ("dbepggeogbaibhgnhhndojpepiihcmeb", "Vimium", "Vim навигация"),
        ("kbfnbcaeplbcioakkpcpgfkobkgalnah", "Grammarly", "Проверка грамматики"),
        ("padekgcemlokbadohgkifijomclgjgif", "Proxy SwitchyOmega", "Прокси менеджер")
    ]
    
    var filtered: [(id: String, name: String, desc: String)] {
        if search.isEmpty { return featured }
        return featured.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.desc.localizedCaseInsensitiveContains(search) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Monochrome search
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Поиск в Chrome Web Store", text: $search)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .font(.system(size: 15, design: .monospaced))
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 1.5))
                .padding()
                .background(Color.white)
                
                if !installStatus.isEmpty {
                    Text(installStatus)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal)
                        .foregroundColor(.black.opacity(0.7))
                }
                
                List {
                    Section(header: Text("УСТАНОВЛЕННЫЕ").font(.system(size: 11, design: .monospaced)).foregroundColor(.black)) {
                        ForEach(extensionManager.installedExtensions) { ext in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.black, lineWidth: 1.2)
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(String(ext.name.prefix(1))).font(.system(size: 15, weight: .bold, design: .monospaced)))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ext.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                                    Text(ext.description).font(.system(size: 11)).foregroundColor(.gray).lineLimit(2)
                                    Text("v\(ext.version) • \(ext.id)").font(.system(size: 9, design: .monospaced)).foregroundColor(.black.opacity(0.4))
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { ext.enabled },
                                    set: { _ in extensionManager.toggle(ext) }
                                ))
                                .toggleStyle(SwitchToggleStyle(tint: .black))
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    extensionManager.remove(ext)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Color.white)
                        }
                    }
                    
                    Section(header: Text("CHROME WEB STORE • РЕКОМЕНДОВАННЫЕ").font(.system(size: 11, design: .monospaced)).foregroundColor(.black)) {
                        ForEach(filtered, id: \.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name).font(.system(size: 15, weight: .medium))
                                    Text(item.desc).font(.system(size: 12)).foregroundColor(.secondary)
                                    Text(item.id).font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
                                }
                                Spacer()
                                if extensionManager.installedExtensions.contains(where: { $0.id == item.id }) {
                                    Text("УСТАНОВЛЕНО")
                                        .font(.system(size: 10, design: .monospaced))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1))
                                } else {
                                    Button {
                                        install(item)
                                    } label: {
                                        Text(isInstalling ? "..." : "УСТАНОВИТЬ")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Color.black)
                                            .cornerRadius(5)
                                    }
                                    .disabled(isInstalling)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.white)
                        }
                    }
                    
                    Section(footer: Text("Dfg Browser устанавливает оригинальные .crx из Chrome Web Store, как Lemur Browser на Android. Manifest V2/V3 поддерживаются.").font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)) {
                        Link(destination: URL(string: "https://chromewebstore.google.com/category/extensions")!) {
                            HStack {
                                Text("Открыть Chrome Web Store в браузере")
                                    .font(.system(size: 13, design: .monospaced))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .foregroundColor(.black)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            }
            .background(Color.white)
            .navigationTitle("Расширения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("DFG")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                }
            }
        }
    }
    
    func install(_ item: (id: String, name: String, desc: String)) {
        isInstalling = true
        installStatus = "Скачивание \(item.name)..."
        Task {
            do {
                try await extensionManager.installFromStore(storeId: item.id, name: item.name)
                await MainActor.run {
                    installStatus = "✓ \(item.name) установлено"
                    isInstalling = false
                }
                try await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { installStatus = "" }
            } catch {
                await MainActor.run {
                    installStatus = "Ошибка: \(error.localizedDescription)"
                    isInstalling = false
                }
            }
        }
    }
}
