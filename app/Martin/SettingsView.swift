import MartinKit
import SwiftUI

struct SettingsView: View {
    @State private var settings = MartinKit.Settings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 32)
                .padding(.top, 46)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .movesWindow()
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    YouSection(settings: $settings)
                    KeysSection()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 36)
            }
        }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .onChange(of: settings) { try? settings.save() }
    }
}

struct SettingsSection<Accessory: View, Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(title)
                Spacer()
                accessory
            }
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 3)
                .padding(.bottom, 12)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Theme.well, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(title: String, summary: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, summary: summary, accessory: { EmptyView() }, content: content)
    }
}

struct FieldRow<Field: View>: View {
    let label: String
    let hint: String
    var divided = true
    @ViewBuilder let field: Field

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 170, alignment: .leading)
            field
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Hairline(divided: divided) }
    }
}

struct Hairline: View {
    let divided: Bool

    var body: some View {
        if divided { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 14) }
    }
}

private struct YouSection: View {
    @Binding var settings: MartinKit.Settings
    @State private var aliases: String
    @State private var keyterms: String

    init(settings: Binding<MartinKit.Settings>) {
        _settings = settings
        _aliases = State(initialValue: settings.wrappedValue.aliases.joined(separator: ", "))
        _keyterms = State(initialValue: settings.wrappedValue.keyterms.joined(separator: ", "))
    }

    var body: some View {
        SettingsSection(title: "You", summary: "How Martin recognises you in a room full of voices.") {
            FieldRow(label: "Name", hint: "As people say it", divided: false) {
                TextField("Your name", text: $settings.name)
            }
            FieldRow(label: "Also called", hint: "Nicknames, handles, usual misspellings") {
                TextField("Eth, ethanc", text: $aliases)
            }
            FieldRow(label: "Words to listen for", hint: "Teammates, projects and topics you follow") {
                TextField("Linear, Postgres, Priya", text: $keyterms, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .onChange(of: aliases) { settings.aliases = Self.split(aliases) }
        .onChange(of: keyterms) { settings.keyterms = Self.split(keyterms) }
    }

    private static func split(_ list: String) -> [String] {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct KeysSection: View {
    var body: some View {
        SettingsSection(title: "Keys", summary: "Kept in your keychain, never in a file.") {
            FieldRow(label: "Deepgram", hint: "Transcribes the room", divided: false) {
                SecretField(key: Secrets.deepgram, prompt: "Paste API key")
            }
        }
    }
}

struct SecretField: View {
    let key: String
    let prompt: String
    @State private var value: String

    init(key: String, prompt: String) {
        self.key = key
        self.prompt = prompt
        _value = State(initialValue: Secrets.get(key) ?? "")
    }

    var body: some View {
        SecureField(prompt, text: $value)
            .onChange(of: value) { Secrets.set(value, for: key) }
    }
}
