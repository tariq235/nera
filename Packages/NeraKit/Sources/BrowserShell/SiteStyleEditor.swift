// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowserCore
import DesignSystem
import EngineKit
import SwiftUI

/// The SiteStyle editor: floats over the top-right of the page so changes show live. Colors, font, Zap (click
/// parts of the page to hide them) and the user's own CSS, saved for the whole site.
struct SiteStyleEditor: View {
    @Bindable var model: AppModel
    let page: any WebPage
    let site: String
    @State private var siteStyle: SiteStyle
    @State private var showsCSS = false

    init(model: AppModel, page: any WebPage, site: String) {
        self.model = model
        self.page = page
        self.site = site
        _siteStyle = State(initialValue: model.siteStyle(for: page) ?? SiteStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.isZapping {
                zapping
            } else {
                colors
                fonts
                zapRow
                cssEditor
                footer
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        .padding(14)
        .onChange(of: siteStyle) { _, new in model.saveSiteStyle(new.isEmpty ? nil : new, site: site) }
        .onChange(of: model.siteStyle(for: page)?.zapped ?? []) { _, zapped in siteStyle.zapped = zapped }  // after Zap
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site Style")
        .accessibilityIdentifier("siteStyle.editor")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("Site Style").font(.system(size: 13.5, weight: .semibold))
                Text(site).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("On", isOn: $siteStyle.isEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .help(siteStyle.isEnabled ? "Turn this style off" : "Turn this style on")
                .accessibilityIdentifier("siteStyle.enabled")
            Button {
                if model.isZapping { model.finishZap() }
                model.isSiteStyleEditorPresented = false
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(PeekButtonStyle(prominent: false))
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close Site Style")
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Colors")
            HStack(spacing: 8) {
                choice("Original", isOn: !siteStyle.isDark && abs(siteStyle.hueRotation) < 0.5 && abs(siteStyle.saturation - 1) < 0.01) {
                    siteStyle.isDark = false
                    siteStyle.hueRotation = 0
                    siteStyle.saturation = 1
                }
                choice("Dark", isOn: siteStyle.isDark) { siteStyle.isDark.toggle() }
                choice("Muted", isOn: siteStyle.saturation < 0.99) { siteStyle.saturation = siteStyle.saturation < 0.99 ? 1 : 0.35 }
            }
            HStack(spacing: 8) {
                Image(systemName: "paintpalette").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $siteStyle.hueRotation, in: -180...180)
                    .accessibilityLabel("Color shift")
                    .accessibilityIdentifier("siteStyle.hue")
            }
            .tint(Color(hue: (siteStyle.hueRotation + 180) / 360, saturation: 0.7, brightness: 0.9))
        }
    }

    private var fonts: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Font")
            Picker("Font", selection: $siteStyle.font) {
                ForEach(SiteStyleFont.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("siteStyle.font")
        }
    }

    private var zapRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Hide")
            HStack {
                Button {
                    model.startZap()
                } label: {
                    Label("Hide Parts of This Page", systemImage: "bolt.fill")
                }
                .accessibilityIdentifier("siteStyle.zap")
                Spacer()
                if !siteStyle.zapped.isEmpty {
                    Button("Restore \(siteStyle.zapped.count)") { siteStyle.zapped = [] }
                        .linkButtonStyle()
                        .help("Show everything you hid again")
                }
            }
        }
    }

    private var zapping: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Click anything on the page to hide it.", systemImage: "cursorarrow.click.2")
                .font(.system(size: 12.5))
            Button {
                model.finishZap()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("siteStyle.zapDone")
        }
    }

    private var cssEditor: some View {
        DisclosureGroup(isExpanded: $showsCSS) {
            TextEditor(text: $siteStyle.css)
                .font(.system(size: 11.5, design: .monospaced))
                .frame(height: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("siteStyle.css")
        } label: {
            sectionTitle("Custom CSS")
        }
    }

    private var footer: some View {
        HStack {
            Text("Saved for every page of \(site).").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            if !siteStyle.isEmpty {
                Button("Delete", role: .destructive) {
                    siteStyle = SiteStyle()
                    model.saveSiteStyle(nil, site: site)
                }
                .linkButtonStyle()
                .font(.system(size: 11.5))
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.primary.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isOn ? Color.accentColor : .clear, lineWidth: 1.2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
