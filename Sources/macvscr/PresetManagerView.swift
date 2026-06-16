import macvscrCore
import AppKit
import SwiftUI

// MARK: - Liquid Glass Modifiers & Fallbacks

/// Liquid-glass button: 统一封装 iOS 26+ 的原生液态玻璃按钮与旧版 macOS 拟物玻璃回退样式。
struct LiquidGlassButtonModifier: ViewModifier {
    var prominent: Bool
    var tint: Color?
    var id: String?
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // 使用 iOS 26+ 原生的 Liquid Glass API。.glassProminent 与 .glass 是
            // 不同的具体 PrimitiveButtonStyle 类型，不能放进同一个三元表达式，
            // 必须分支构造，再用统一修饰继续链式调用。
            if let id = id, let namespace = namespace {
                styled(content)
                    .glassEffectID(id, in: namespace)
            } else {
                styled(content)
            }
        } else {
            // 降级回退：纯正的 macOS 拟物液态玻璃按钮
            content.buttonStyle(MacGlassButtonStyle(color: tint))
        }
    }

    /// Apply the native glass button style (prominent or regular) + tint.
    /// macOS 26+ only — only called from the `if #available(macOS 26.0)` arm.
    @available(macOS 26.0, iOS 26.0, *)
    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.glassProminent).tint(tint ?? .accentColor)
        } else {
            content.buttonStyle(.glass).tint(tint ?? .accentColor)
        }
    }
}

/// A vibrancy material with a vertical gradient mask.
/// 在 iOS 26+ 上利用原生的 glassEffect 进行更真实的光线散射折射。
struct ProgressiveGlassBackground: View {
    var overhang: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let topBleed: CGFloat = 80  // 向上延伸以覆盖标题栏
            let totalHeight = topBleed + geo.size.height + overhang
            let solidRatio = (topBleed + geo.size.height) / totalHeight

            Group {
                if #available(macOS 26.0, iOS 26.0, *) {
                    Rectangle()
                        .fill(Color.clear)
                        .glassEffect(.regular, in: .rect)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
            }
            .frame(height: totalHeight)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: solidRatio),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .offset(y: -topBleed)
            .ignoresSafeArea()
        }
    }
}

/// 扩展 Shape，使其可以轻松应用静态的 Liquid Glass 效果（适用于非交互式面板如显示器预览区）
extension Shape {
    @ViewBuilder
    func applyStaticGlass(cornerRadius: CGFloat = 0) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // Branch (not ternary): .rect(cornerRadius:) and .rect are
            // different concrete Shape types and can't unify in `some Shape`.
            if cornerRadius > 0 {
                self.fill(Color.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                self.fill(Color.clear).glassEffect(.regular, in: .rect)
            }
        } else {
            self.fill(.regularMaterial)
        }
    }
}

// MARK: - Legacy Mac Glass Style (Fallback)

struct MacGlassButtonStyle: ButtonStyle {
    var color: Color? = nil
    var cornerRadius: CGFloat = 8
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                    if let color = color, isEnabled {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color.opacity(configuration.isPressed ? 0.25 : 0.12))
                    }
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(isEnabled ? 0.45 : 0.15),
                                .white.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: (isEnabled ? color?.opacity(0.2) : nil) ?? .black.opacity(0.04),
                radius: 2, x: 0, y: 1
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - Availability-isolated modifiers

extension View {
    @ViewBuilder
    func macGlassBackground(_ material: Material = .regularMaterial) -> some View {
        self.background(material)
    }

    @ViewBuilder
    func macContainerBackground(_ material: Material = .regularMaterial) -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(material, for: .window)
        } else {
            self
        }
    }
}

// MARK: - Label styles

struct IconLeadingLabelStyle: LabelStyle {
    var spacing: CGFloat = 6
    var iconVerticalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            configuration.icon
                .padding(.vertical, iconVerticalPadding)
            configuration.title
        }
    }
}

// MARK: - Preset Manager View

struct PresetManagerView: View {

    @ObservedObject var library: PresetLibrary
    @ObservedObject var preview: PreviewState
    let liveConfig: () -> (width: UInt32, height: UInt32, hidpi: Bool, dpiPercent: Int?)

    let onApply: (CustomPreset) -> Void
    let onSave: (CustomPreset) -> Void
    let onConfirm: (CustomPreset) -> Void
    let onRevert: () -> Void

    @State private var selectedID: UUID?
    /// Preset awaiting removal confirmation; drives the alert.
    @State private var pendingRemovalID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            if let id = selectedID, let idx = library.presets.firstIndex(where: { $0.id == id }) {
                PresetDetailView(
                    libraryPreset: Binding(
                        get: { library.presets[idx] },
                        set: { library.update($0) }
                    ),
                    preview: preview,
                    onApply: onApply,
                    onSave: onSave,
                    onConfirm: onConfirm,
                    onRevert: onRevert
                )
            } else {
                EmptyDetail()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { ensureSelection() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(library.presets) { p in sidebarRow(p).tag(p.id) }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { footerBar }
        }
        .alert(
            "Delete \"\(pendingRemovalName)\"?",
            isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            )
        ) {
            Button("Delete", role: .destructive) { removeConfirmed() }
            Button("Cancel", role: .cancel) { pendingRemovalID = nil }
        } message: {
            Text("This preset will be removed from your library. This cannot be undone.")
        }
    }

    private func sidebarRow(_ p: CustomPreset) -> some View {
        let trimmed = p.name.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 1) {
            Text(trimmed.isEmpty ? "Untitled" : trimmed).lineLimit(1)
            Text(p.resolutionLabel)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var footerBar: some View {
        // 利用 iOS 26 / macOS 26 的 GlassEffectContainer 合并相邻按钮光效
        Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 6) {
                    footerBarButtons
                }
            } else {
                footerBarButtons
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
    }

    private var footerBarButtons: some View {
        HStack(spacing: 6) {
            Button(action: addPreset) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .imageScale(.medium)
            .help("Add preset (uses current display settings)")

            Button(action: confirmRemove) {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .imageScale(.medium)
            .disabled(selectedID == nil)
            .help("Remove selected preset")

            Spacer()
        }
    }

    // MARK: Actions

    private func addPreset() {
        let live = liveConfig()
        let p = CustomPreset(
            name: nextDefaultName(),
            logicalWidth: live.width,
            logicalHeight: live.height,
            hidpi: live.hidpi,
            dpiPercent: live.dpiPercent)
        library.append(p)
        selectedID = p.id
    }

    private func nextDefaultName() -> String {
        let taken = Set(library.presets.map { $0.name.trimmingCharacters(in: .whitespaces) })
        var i = 1
        while taken.contains("Custom Preset \(i)") { i += 1 }
        return "Custom Preset \(i)"
    }

    /// Open the confirmation dialog for deleting the selected preset.
    private func confirmRemove() {
        guard let id = selectedID else { return }
        pendingRemovalID = id
    }

    /// Delete the preset that was confirmed in the alert.
    private func removeConfirmed() {
        guard let id = pendingRemovalID else { return }
        library.remove(id: id)
        if selectedID == id { selectedID = library.presets.first?.id }
        pendingRemovalID = nil
    }

    /// The name to show in the confirmation alert, or "" if not pending.
    private var pendingRemovalName: String {
        guard let id = pendingRemovalID,
              let p = library.find(id: id) else { return "" }
        let trimmed = p.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func ensureSelection() {
        if selectedID == nil || !library.contains(id: selectedID!) {
            selectedID = library.presets.first?.id
        }
    }
}

// MARK: - Detail View

private struct PresetDetailView: View {
    @Binding var libraryPreset: CustomPreset
    @ObservedObject var preview: PreviewState

    let onApply: (CustomPreset) -> Void
    let onSave: (CustomPreset) -> Void
    let onConfirm: (CustomPreset) -> Void
    let onRevert: () -> Void

    @StateObject private var editor = PresetEditorModel()
    @State private var saveFlash = false
    @State private var keepWidth = true

    @Namespace private var headerGlassNamespace

    private var isDirty: Bool { editor.differs(from: libraryPreset) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MonitorPreview(preset: editor.snapshot())
                    .padding(.vertical, 24)
                form
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .background(ProgressiveGlassBackground(overhang: 120))
        }
        .navigationSubtitle(subtitle)
        .onAppear { editor.load(libraryPreset) }
        .onChange(of: libraryPreset) { newLib in editor.load(newLib) }
    }

    private var subtitle: String {
        if preview.active?.id == editor.id, let n = preview.secondsRemaining {
            return "Previewing · reverts in \(n)s"
        }
        return editor.resolutionLabel
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    editor.name.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Untitled Preset" : editor.name
                )
                .font(.title2).fontWeight(.bold)

                Text(headerSubtitleLine)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)

            if #available(macOS 26.0, iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    actionButtonsHStack
                }
            } else {
                actionButtonsHStack
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var headerSubtitleLine: String {
        var bits = ["Logical \(editor.logicalWidth)×\(editor.logicalHeight)"]
        bits.append(editor.hidpi ? "Retina " + editor.densitySuffix : "Standard")
        if let r = preview.secondsRemaining, preview.active?.id == editor.id {
            bits.append("Previewing · \(r)s")
        }
        return bits.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var actionButtonsHStack: some View {
        let isPreviewing = preview.active?.id == editor.id
        let snapshot = editor.snapshot()
        HStack(spacing: 12) {

            Button {
                onSave(snapshot)
                withAnimation(.easeOut(duration: 0.25)) { saveFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.6)) { saveFlash = false }
                }
            } label: {
                if saveFlash {
                    Label("Saved", systemImage: "checkmark")
                } else {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }
            .labelStyle(IconLeadingLabelStyle())
            .modifier(
                LiquidGlassButtonModifier(
                    prominent: saveFlash,
                    tint: saveFlash ? .green : .accentColor,
                    id: "saveAction",
                    namespace: headerGlassNamespace
                )
            )
            .disabled(!saveFlash && !isDirty)
            .help("Save the preset definition (does not change the display)")

            if isPreviewing {
                Button {
                    onRevert()
                } label: {
                    Label(
                        "Revert (\(preview.secondsRemaining ?? 0)s)",
                        systemImage: "arrow.uturn.backward")
                }
                .labelStyle(IconLeadingLabelStyle())
                .modifier(
                    LiquidGlassButtonModifier(
                        prominent: false,
                        tint: .orange,
                        id: "revertAction",
                        namespace: headerGlassNamespace
                    )
                )
                .help("Cancel this preview and restore the previous configuration")
                .transition(.opacity.combined(with: .scale))

                Button {
                    onConfirm(snapshot)
                } label: {
                    Label("Confirm", systemImage: "checkmark.circle.fill")
                }
                .labelStyle(IconLeadingLabelStyle())
                .modifier(
                    LiquidGlassButtonModifier(
                        prominent: true,
                        tint: .green,
                        id: "confirmAction",
                        namespace: headerGlassNamespace
                    )
                )
                .help("Keep this configuration: save the preset and apply permanently")
                .transition(.opacity.combined(with: .scale))
            } else {
                Button {
                    onApply(snapshot)
                } label: {
                    Label("Apply", systemImage: "play.fill")
                }
                .labelStyle(IconLeadingLabelStyle())
                .modifier(
                    LiquidGlassButtonModifier(
                        prominent: true,
                        tint: .accentColor,
                        id: "applyAction",
                        namespace: headerGlassNamespace
                    )
                )
                .help("Preview on the display for 10 seconds")
                .transition(.opacity.combined(with: .scale))
            }
        }
        // 当预览状态切换时触发玻璃 Morphing (形变动画)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isPreviewing)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: saveFlash)
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $editor.name)
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in the tray menu. Names may repeat.").font(.caption)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Width").font(.caption).foregroundStyle(.secondary)
                        TextField("Width", value: Binding(
                            get: { editor.logicalWidth },
                            set: { editor.setWidth($0) }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .help(editor.lockAspect ? "Height follows aspect" : "")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Height").font(.caption).foregroundStyle(.secondary)
                        TextField("Height", value: Binding(
                            get: { editor.logicalHeight },
                            set: { editor.setHeight($0) }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Toggle("Lock aspect ratio", isOn: $editor.lockAspect).toggleStyle(.switch)
            } header: {
                Text("Resolution")
            } footer: {
                Text(
                    "Logical pixels. Physical = \(editor.physicalWidth)×\(editor.physicalHeight)."
                ).font(.caption)
            }

            Section {
                Picker("Preset ratio", selection: Binding(
                    get: {
                        if case .standard(let r) = editor.aspect { return r.rawValue }
                        return "__custom__"
                    },
                    set: { tag in
                        if let r = Geometry.Ratio(rawValue: tag) {
                            if keepWidth { editor.setAspect(r.factor) }
                            else { editor.setAspectKeepingHeight(r.factor) }
                        }
                    }
                )) {
                    ForEach(Geometry.Ratio.allCases, id: \.rawValue) { r in
                        Text(r.label).tag(r.rawValue)
                    }
                    Divider()
                    Text("Custom · \(Geometry.reducedRatio(width: editor.logicalWidth, height: editor.logicalHeight))")
                        .tag("__custom__")
                }
                .pickerStyle(.menu).labelsHidden()

                HStack(spacing: 6) {
                    ratioField(value: ratioNumeratorBinding)
                    Text(":").foregroundStyle(.secondary)
                    ratioField(value: ratioDenominatorBinding)
                    Spacer(minLength: 12)
                    Picker("Anchor", selection: $keepWidth) {
                        Text("Keep Width").tag(true)
                        Text("Keep Height").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            } header: {
                Text("Aspect")
            } footer: {
                Text(
                    "Pick a standard ratio, or enter W:H. Keep Width/Height chooses which dimension stays fixed."
                ).font(.caption)
            }

            Section {
                Toggle("HiDPI / Retina", isOn: $editor.hidpi).toggleStyle(.switch)
                if editor.hidpi {
                    CustomDpiForm(model: editor)
                }
            } header: {
                Text("Density")
            } footer: {
                if editor.hidpi {
                    Text("Logical \(editor.logicalWidth)×\(editor.logicalHeight) → physical \(editor.physicalWidth)×\(editor.physicalHeight). \(dpiFooter())").font(.caption)
                } else {
                    Text("Doubles physical pixels for a Retina panel identity.").font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Derived helpers (all read from the editor model)

    /// One-line density summary for the section footer.
    private func dpiFooter() -> String {
        let pct = editor.effectiveDpiPercent
        let ppi = editor.ppi
        let (w, h) = editor.screenMM
        return "\(editor.densitySuffix) · \(pct)% · \(Int(ppi)) ppi · \(String(format: "%.1f", w / 10))×\(String(format: "%.1f", h / 10)) cm."
    }

    private var ratioPair: (num: UInt32, den: UInt32) {
        let a = editor.aspect
        if case .standard(let r) = a {
            let parts = r.rawValue.split(separator: ":")
            if parts.count == 2, let n = UInt32(parts[0]), let d = UInt32(parts[1]) {
                return (n, d)
            }
        }
        func gcd(_ x: UInt32, _ y: UInt32) -> UInt32 { y == 0 ? x : gcd(y, x % y) }
        guard editor.logicalWidth > 0, editor.logicalHeight > 0 else { return (16, 9) }
        let g = gcd(editor.logicalWidth, editor.logicalHeight)
        return (editor.logicalWidth / g, editor.logicalHeight / g)
    }

    private var ratioNumeratorBinding: Binding<Int> {
        Binding(
            get: { Int(ratioPair.num) },
            set: { newN in applyRatio(num: max(1, UInt32(newN)), den: ratioPair.den) }
        )
    }

    private var ratioDenominatorBinding: Binding<Int> {
        Binding(
            get: { Int(ratioPair.den) },
            set: { newD in applyRatio(num: ratioPair.num, den: max(1, UInt32(newD))) }
        )
    }

    private func applyRatio(num: UInt32, den: UInt32) {
        guard den > 0 else { return }
        let factor = Double(num) / Double(den)
        if keepWidth {
            editor.setAspect(factor)
        } else {
            editor.setAspectKeepingHeight(factor)
        }
    }

    private func ratioField(value: Binding<Int>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 56)
    }
}

// MARK: - iMac preview

private struct MonitorPreview: View {
    let preset: CustomPreset
    @State private var wallpaper: NSImage?

    private static let bezelMM: CGFloat = 5
    private static let rimMM: CGFloat = 4
    private static let neckHMM: CGFloat = 45
    private static let neckWMM: CGFloat = 60
    private static let baseHMM: CGFloat = 14
    private static let outerCRMM: CGFloat = 10
    private static let screenCRMM: CGFloat = 3

    var body: some View {
        let (swMM, shMM) = preset.screenMM
        let screenW = max(1, CGFloat(swMM))
        let screenH = max(1, CGFloat(shMM))

        let bodyW = screenW + (Self.bezelMM + Self.rimMM) * 2
        let bodyH = screenH + (Self.bezelMM + Self.rimMM) * 2
        let neckH = Self.neckHMM
        let baseW = Self.neckWMM * 2.0
        let baseH = Self.baseHMM

        let totalW = max(bodyW, baseW)
        let totalH = bodyH + neckH + baseH
        let safe: CGFloat = 16

        VStack(spacing: 6) {
            caption

            GeometryReader { geo in
                let availW = max(1, geo.size.width - safe * 2)
                let availH = max(1, geo.size.height - safe * 2)
                let scale = min(availW / totalW, availH / totalH)
                let drawnW = totalW * scale
                let drawnH = totalH * scale

                let machineX = geo.size.width / 2
                let machineTopY = safe + drawnH / 2

                ZStack {
                    Color.clear

                    machine(
                        screenW: screenW, screenH: screenH,
                        bodyW: bodyW, bodyH: bodyH,
                        neckH: neckH, baseW: baseW, baseH: baseH,
                        totalW: totalW, totalH: totalH
                    )
                    .scaleEffect(scale)
                    .frame(width: drawnW, height: drawnH)
                    .position(x: machineX, y: machineTopY)

                    let screenCenterY =
                        machineTopY - drawnH / 2
                        + (Self.bezelMM + Self.rimMM) * scale
                        + screenH * scale / 2

                    unscaledLabels
                        .position(x: machineX, y: screenCenterY)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 250)
        }
        .onAppear { loadWallpaper() }
    }

    private var caption: some View {
        let (w, h) = preset.screenMM
        let sizeStr = String(format: "%.1f × %.1f cm", w / 10, h / 10)
        let dpiPart: String = preset.hidpi
            ? "  ·  \(Geometry.densitySuffix(scale: preset.scale)) (\(Int(preset.ppi)) ppi)"
            : ""
        return HStack(spacing: 10) {
            Text("\(preset.physicalWidth)×\(preset.physicalHeight) px")
            Text("\(sizeStr)  ·  \(String(format: "%.0f\"", preset.diagonalInches))\(dpiPart)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var unscaledLabels: some View {
        VStack(spacing: 1) {
            Text("\(preset.logicalWidth)×\(preset.logicalHeight)")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
            Text(Geometry.reducedRatio(width: preset.logicalWidth, height: preset.logicalHeight))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func machine(
        screenW: CGFloat, screenH: CGFloat,
        bodyW: CGFloat, bodyH: CGFloat,
        neckH: CGFloat, baseW: CGFloat, baseH: CGFloat,
        totalW: CGFloat, totalH: CGFloat
    ) -> some View {
        let bezel = Self.bezelMM
        let rim = Self.rimMM

        return ZStack(alignment: .top) {
            Color.clear.frame(width: totalW, height: totalH)

            VStack(spacing: 0) {
                // 使用原生的静态玻璃面板重构 iMac 机身材质
                ZStack {
                    RoundedRectangle(cornerRadius: Self.outerCRMM, style: .continuous)
                        .applyStaticGlass(cornerRadius: Self.outerCRMM)
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.outerCRMM, style: .continuous)
                                .strokeBorder(.black.opacity(0.15), lineWidth: 1)
                        )

                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            Color.clear.frame(height: bezel)
                            Circle()
                                .fill(.secondary.opacity(0.8))
                                .frame(width: 4, height: 4)
                                .padding(.top, -1)
                        }
                        .frame(maxWidth: .infinity)

                        ZStack {
                            Color.black
                            screenInterior(width: screenW, height: screenH)
                        }
                        .frame(width: screenW, height: screenH)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Self.screenCRMM, style: .continuous))

                        Color.clear.frame(height: bezel)
                    }
                    .padding(.horizontal, bezel)
                    .padding(rim)
                }
                .frame(width: bodyW, height: screenH + bezel * 2 + rim * 2)

                Rectangle()
                    .applyStaticGlass()
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.1), lineWidth: 1))
                    .frame(width: Self.neckWMM, height: neckH)

                Rectangle()
                    .applyStaticGlass()
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.1), lineWidth: 1))
                    .frame(width: baseW, height: baseH)
            }
            .frame(width: totalW)
        }
    }

    @ViewBuilder
    private func screenInterior(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if let img = wallpaper {
                Image(nsImage: img).resizable().scaledToFill()
            }
            Rectangle().fill(.ultraThinMaterial)
        }
        .clipped()
    }

    private func loadWallpaper() {
        guard let screen = NSScreen.main else { return }
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            wallpaper = NSImage(contentsOf: url)
        }
    }
}

// MARK: - Empty state

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 16) {
            // 在 iOS 26+ 下，对图标进行精致的 Liquid Glass 包装
            if #available(macOS 26.0, iOS 26.0, *) {
                Image(systemName: "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(32)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(32)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            Text("No Preset Selected").font(.headline).foregroundStyle(.secondary)
            Text(
                "Add a preset with + to get started. New presets use the current display settings."
            )
            .font(.subheadline).foregroundStyle(.tertiary)
            .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Custom Presets")
    }
}

// MARK: - Inline Custom DPI form

/// Mirrors the tray's Custom DPI dialog inside the preset manager: a percentage
/// TextField + a Keep Physical | Keep Logical segmented control, with a live
/// read-out of the resulting physical / logical pixels.
///
/// - Keep Physical (default): changing % re-derives logical from the held
///   physical pixel count (logical = physical / scale).
/// - Keep Logical: changing % only updates dpiPercent; logical stays, physical
///   follows (physical = logical × scale).
private struct CustomDpiForm: View {
    @ObservedObject var model: PresetEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DPI scaling").font(.caption).foregroundStyle(.secondary)
            // [250]%   ………   Keep Physical | Keep Logical
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    TextField("", value: Binding(
                        get: { model.effectiveDpiPercent },
                        set: { model.setDpi($0) }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("%").foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Picker("", selection: $model.dpiKeepPhysical) {
                    Text("Keep Physical").tag(true)
                    Text("Keep Logical").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            // Live read-out of the resulting physical / logical pixels.
            Text(resultLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultLine: String {
        let ppi = model.ppi
        let (w, h) = model.screenMM
        return "physical \(model.physicalWidth)×\(model.physicalHeight) · logical \(model.logicalWidth)×\(model.logicalHeight) · \(Int(ppi)) ppi · \(String(format: "%.1f", w / 10))×\(String(format: "%.1f", h / 10)) cm"
    }
}
