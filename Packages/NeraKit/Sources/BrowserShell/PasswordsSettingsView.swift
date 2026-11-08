// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if os(macOS)
    import AppKit
    import Import
    import SwiftUI
    import BrowserData

    /// Settings › Passwords: fill passwords on websites with a password manager's extension, and move saved
    /// passwords from another browser into Apple Passwords. Nera never stores passwords itself.
    struct PasswordsSettingsView: View {
        @Bindable var model: AppModel
        @State private var installing: PasswordManager?
        @State private var moving: ImportSource?

        var body: some View {
            Form {
                Section {
                    // Only managers on this Mac (or already set up): the others can't fill anything.
                    ForEach(PasswordManager.allCases.filter { $0.isOnThisMac || model.hasExtension(for: $0) }) { manager in
                        managerRow(manager)
                    }
                    if model.needsRelaunchForExtensions {
                        HStack {
                            Label("Restart Nera to start filling passwords.", systemImage: "arrow.clockwise")
                            Spacer()
                            Button("Restart Now") { model.relaunch() }
                        }
                    }
                } header: {
                    Text("Fill Passwords on Websites")
                } footer: {
                    Text(
                        "Nera fills passwords through your password manager's extension: it suggests logins on sign-in pages and saves new ones. Apple Passwords asks for a code the first time."
                    )
                    .foregroundStyle(.secondary)
                }
                if !sources.isEmpty {
                    Section {
                        ForEach(sources) { source in
                            HStack {
                                (source.appIcon ?? Image(systemName: "globe")).resizable().frame(width: 22, height: 22)
                                Text(source.displayName)
                                Spacer()
                                Button("Move to Apple Passwords…") { moving = source }
                                    .accessibilityIdentifier("passwords.move.\(source.rawValue)")
                            }
                        }
                    } header: {
                        Text("Saved Passwords in Other Browsers")
                    } footer: {
                        Text("Your passwords go to Apple Passwords, where every app and device can use them. Nera keeps no copy.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .sheet(item: $moving) { source in MovePasswordsView(model: model, source: source) }
        }

        /// Chromium browsers on this Mac with saved passwords.
        private var sources: [ImportSource] {
            ImportSource.allCases.filter { source in
                guard source.isChromium, let profile = source.dataDirectory else { return false }
                return FileManager.default.fileExists(atPath: profile.appending(path: "Login Data").path)
            }
        }

        private func managerRow(_ manager: PasswordManager) -> some View {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: manager.appPath)).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(manager.name)
                    Text(status(manager)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.hasExtension(for: manager) {
                    Label("Set Up", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
                } else if manager.isOnThisMac {
                    Button(installing == manager ? "Setting Up…" : "Set Up") {
                        installing = manager
                        Task {
                            if await !model.installPasswordManager(manager) {
                                model.notice = "\(manager.name) couldn't be set up. Check your internet connection and try again."
                            }
                            installing = nil
                        }
                    }
                    .disabled(installing != nil || !model.supportsExtensions)
                    .accessibilityIdentifier("passwords.setUp.\(manager.rawValue)")
                }
            }
        }

        private func status(_ manager: PasswordManager) -> String {
            if model.hasExtension(for: manager) { return "Fills passwords in Nera" }
            return manager.isOnThisMac ? "On this Mac" : "Not on this Mac"
        }
    }

    /// Moves another browser's saved passwords into Apple Passwords: Nera prepares a private file, the user
    /// imports it in Passwords (File ▸ Import Passwords), and Nera deletes the file.
    struct MovePasswordsView: View {
        let model: AppModel
        let source: ImportSource
        @Environment(\.dismiss) private var dismiss
        @State private var export: PasswordExport?
        @State private var isWorking = false
        @State private var failed = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    (source.appIcon ?? Image(systemName: "globe")).resizable().frame(width: 40, height: 40)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: PasswordManager.applePasswords.appPath)).resizable()
                        .frame(width: 40, height: 40)
                }
                Text("Move Passwords to Apple Passwords").font(.title2.weight(.semibold))
                if let export {
                    Text("\(export.count) passwords from \(source.displayName) are ready.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Click Open Passwords.")
                        step(2, "In Passwords, choose File ▸ Import Passwords…")
                        step(3, "Pick “\(export.file.lastPathComponent)” (Nera shows it in Finder).")
                        step(4, "Come back and click Done. Nera deletes the file.")
                    }
                    .padding(12)
                    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if failed {
                    Label(
                        "Nera couldn't read \(source.displayName)'s passwords: access wasn't allowed, or there are none saved.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Nera reads the passwords saved in \(source.displayName) and prepares them for Apple Passwords. macOS asks you to allow this: choose Always Allow."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button(export == nil ? "Cancel" : "Done") { dismiss() }
                        .keyboardShortcut(export == nil ? .cancelAction : .defaultAction)
                        .accessibilityIdentifier("passwords.done")
                    if let export {
                        Button("Open Passwords") { model.openPasswordsForImport(export) }
                            .accessibilityIdentifier("passwords.open")
                    } else if !failed {
                        Button(isWorking ? "Preparing…" : "Continue") {
                            isWorking = true
                            Task {
                                export = await model.preparePasswordExport(from: source)
                                failed = export == nil
                                isWorking = false
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking)
                        .accessibilityIdentifier("passwords.continue")
                    }
                }
            }
            .padding(24)
            .frame(width: 460)
            .onDisappear { model.finishPasswordExport(export) }
        }

        private func step(_ number: Int, _ text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
                Text(text)
            }
        }
    }
#endif
