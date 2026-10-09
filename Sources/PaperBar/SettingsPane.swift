import AppKit
import SwiftUI

struct SettingsPane: View {
    @EnvironmentObject private var store: PaperStore
    let onClose: () -> Void
    @State private var keyInput = ""

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var s: Strings { store.s }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Label(s.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(s.settings).font(.headline)
                Spacer()
                Color.clear.frame(width: 70, height: 1)   // 제목 가운데 정렬용
            }
            .padding(12)

            Divider()

            Form {
                Section {
                    Picker(s.language, selection: $store.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName(in: s)).tag(lang)
                        }
                    }
                }

                Section("Semantic Scholar") {
                    if store.hasS2Key {
                        HStack {
                            Label(s.s2KeySaved, systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button(s.deleteKey, role: .destructive) { store.deleteS2Key() }
                        }
                    } else {
                        HStack {
                            SecureField(s.apiKey, text: $keyInput)
                                .onSubmit(save)
                            // 메뉴바 앱은 편집 메뉴가 없어 ⌘V 가 안 먹을 수 있어서 버튼도 둠
                            Button(s.paste) {
                                keyInput = NSPasteboard.general.string(forType: .string)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            }
                            Button(s.save, action: save)
                                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    Text(s.s2Explainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(s.getFreeKey, destination: URL(string: "https://www.semanticscholar.org/product/api#api-key-form")!)
                        .font(.caption)
                    Picker(s.citedWindow, selection: $store.s2WindowDays) {
                        ForEach([30, 60, 90, 180], id: \.self) { days in
                            Text(s.lastNDays(days)).tag(days)
                        }
                    }
                }

                Section(s.sectionFilter) {
                    Toggle(s.strictToggle, isOn: $store.strictMatch)
                    Text(s.strictExplainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(s.sectionUpdates) {
                    Picker(s.dailyRefreshTime, selection: $store.refreshHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    Toggle(s.launchAtLogin, isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    ))
                    .disabled(!store.canLaunchAtLogin)
                }

                Section {
                    HStack {
                        Link(s.openHFTrending, destination: URL(string: "https://huggingface.co/papers/trending")!)
                            .font(.caption)
                        Spacer()
                        Button(s.quit) { NSApplication.shared.terminate(nil) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func save() {
        store.saveS2Key(keyInput)
        keyInput = ""
    }
}
