import AppKit
import PingScopeCore
import SwiftUI

extension SettingsRootView {
    var display: some View {
        SettingsPane {
            SettingsSection("Menu Bar") {
                SettingsRow(systemImage: "rectangle.2.swap", tint: .indigo, title: "Display style") {
                    Picker("Display style", selection: $model.displayMode) {
                        ForEach(PingScopeDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                SettingsRow(systemImage: "chart.xyaxis.line", tint: .blue, title: "Graph range") {
                    Picker("Menu bar range", selection: $model.selectedRange) {
                        ForEach(TimeRange.displayCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
            SettingsSection("Overlay") {
                SettingsToggleRow(systemImage: "rectangle.on.rectangle", tint: .blue, title: "Show overlay", isOn: Binding(
                    get: { model.overlayVisible },
                    set: { isVisible in
                        DebugLog.write("settings overlay show changed visible=\(isVisible)")
                        if isVisible {
                            AppDelegate.shared?.showOverlay()
                        } else {
                            AppDelegate.shared?.hideOverlay()
                        }
                    }
                ))
                SettingsToggleRow(systemImage: "pin.fill", tint: .orange, title: "Always on top", isOn: Binding(
                    get: { model.overlayAlwaysOnTop },
                    set: {
                        DebugLog.write("settings overlay alwaysOnTop changed value=\($0)")
                        model.overlayAlwaysOnTop = $0
                        AppDelegate.shared?.applyOverlayBehavior()
                    }
                ))
                SettingsToggleRow(systemImage: "arrow.up.left.and.arrow.down.right", tint: .purple, title: "Compact overlay", isOn: Binding(
                    get: { model.overlayCompactMode },
                    set: {
                        DebugLog.write("settings overlay compact changed value=\($0)")
                        AppDelegate.shared?.setOverlayCompactMode($0)
                    }
                ))
                SettingsRow(systemImage: "slider.horizontal.3", tint: .teal, title: "Window opacity") {
                    HStack(spacing: 10) {
                        Slider(value: Binding(
                            get: { model.overlayOpacity },
                            set: {
                                model.overlayOpacity = $0
                                AppDelegate.shared?.applyWindowOpacity()
                            }
                        ), in: 0.55...1)
                        .frame(width: 160)
                        Text("\(Int((model.overlayOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                SettingsRow(systemImage: "aspectratio", tint: .gray, title: "Saved size") {
                    Text("\(Int(model.overlayFrame.width)) x \(Int(model.overlayFrame.height))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                SettingsRow(systemImage: "scope", tint: .gray, title: "Position") {
                    Button("Reset Overlay Position") {
                        model.resetOverlayFrame()
                        AppDelegate.shared?.resetOverlayFrame()
                    }
                }
            }
        }
    }

}
