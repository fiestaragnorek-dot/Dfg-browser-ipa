# Dfg Browser • iOS

Чёрно-белый браузер для iOS с **настоящей поддержкой Chrome Web Store**, как Lemur Browser на Android.

![Monochrome](https://img.shields.io/badge/style-black%26white-000000)
![iOS](https://img.shields.io/badge/iOS-16%2B-black)
![Extensions](https://img.shields.io/badge/Chrome%20Extensions-CRX-white)

> Dfg Browser v1.1 • Monochrome Edition

---

## Что это

Полноценный iOS браузер (WKWebView) в чёрно-белом стиле.

Главное:
- **Реальный Chrome Web Store** внутри приложения
  - Открывается `chromewebstore.google.com` через desktop User-Agent
  - WKWebView с Chrome 126 UA: `Mozilla/5.0 (Macintosh...) Chrome/126...`
  - Инжектится кнопка **«УСТАНОВИТЬ В DFG BROWSER»** на страницах расширений
- **Установка .crx как в Lemur**
  - Скачивание через `clients2.google.com/service/update2/crx`
  - Распаковка CRX3 → ZIP (ZIPFoundation)
  - Чтение `manifest.json` V2/V3
  - Инжект `content_scripts` в WKUserContentController
- Чистый black & white UI, SF Mono
- Вкладки, поиск, приватность

Это не Safari-обёртка. Это настоящий браузерный движок с extension bridge.

---

## Скриншоты / структура

```
DfgBrowserApp.swift          App entry, BrowserState
ContentView.swift            Black&white toolbar + tabs
BrowserView.swift            WKWebView + extension injection
Extensions/
  ExtensionManager.swift     CRX downloader / installer
  ChromeStoreWebView.swift   НАСТОЯЩИЙ Chrome Web Store WKWebView
SettingsView.swift           Настройки
```

---

## Сборка локально

```bash
git clone <repo>
cd DfgBrowser
open DfgBrowser.xcodeproj
```

Xcode 15+, iOS 16+
- Swift Package **ZIPFoundation** подтянется автоматически
- Signing: свой Apple ID → Personal Team
- Product → Archive → Distribute → Ad Hoc → .ipa

CLI unsigned:
```bash
xcodebuild -project DfgBrowser.xcodeproj -scheme DfgBrowser -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

APP=$(find build -name DfgBrowser.app | head -1)
mkdir -p Payload && cp -R "$APP" Payload/
zip -r DfgBrowser-unsigned.ipa Payload
```

---

## Сборка через GitHub Actions (рекомендуется)

Репозиторий уже содержит `.github/workflows/build-ipa.yml`

1. Залей этот проект на GitHub:
```bash
git init
git add .
git commit -m "Dfg Browser 1.1"
git branch -M main
git remote add origin https://github.com/<you>/dfg-browser-ios.git
git push -u origin main
```

2. Открой вкладку **Actions** → `Build Dfg Browser IPA` → Run

3. Через ~4-6 минут в Artifacts:
   - `DfgBrowser-unsigned` → **DfgBrowser-unsigned.ipa**
   - `DfgBrowser-xcarchive` → для подписи

Скачай IPA → подпиши:
- **Sideloadly** (Win/Mac)
- **AltStore**
- **TrollStore** (iOS 15-16)
- или `ios-app-signer` + свой сертификат

---

## Как работают расширения

1. Нажми 🧩 внизу
2. Откроется **реальный chromewebstore.google.com**
3. Найди любое расширение → открой страницу
4. Внизу справа появится чёрная кнопка **«УСТАНОВИТЬ В DFG BROWSER»**
5. Браузер скачает .crx, распакует, установит
6. content_scripts автоматически инжектятся в каждую страницу

Поддерживаются:
- uBlock Origin
- Tampermonkey / Violentmonkey
- Dark Reader
- Bitwarden / LastPass
- SingleFile, Vimium, Grammarly, SwitchyOmega … любое из Store

Manifest V2 и V3.

---

## Технические детали

- **Engine:** WKWebView, iOS 16+
- **UA:** `Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 DfgBrowser/1.1`
- **CRX install URL:** `https://clients2.google.com/service/update2/crx?response=redirect&prodversion=126.0&acceptformat=crx2,crx3&x=id%3D<EXT_ID>%26uc`
- **Injection:** `WKUserContentController.addUserScript`
- **Download:** `WKNavigationResponsePolicy.download` + `WKDownloadDelegate`
- **Storage:** UserDefaults (JSON InstalledExtension)
- **Dependencies:** ZIPFoundation (SPM)

iOS ограничивает движок WebKit'ом — это требование Apple. Dfg делает максимально близко к Lemur: те же CRX, тот же Store, тот же инжект.

---

## Bundle ID

```
com.dfgbrowser.ios
Dfg Browser
Version 1.0.3 (103)
```

Меняй Bundle ID под свой сертификат перед подписью.

---

## Лицензия

MIT — делай что хочешь.

---

**DFG BROWSER • BLACK & WHITE • BUILT FOR CHROME EXTENSIONS ON iOS**
