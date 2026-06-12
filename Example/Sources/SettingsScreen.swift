import SwiftUI

/// Lets the user tune every detector parameter and pick which tag families are
/// active. Reachable by swiping left from the camera.
struct SettingsScreen: View {
    @ObservedObject var settings: DetectorSettings
    @ObservedObject var camera: CameraManager

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Resolution / FPS", selection: formatSelection) {
                        ForEach(camera.availableFormats) { format in
                            Text(format.label).tag(format.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Live feed")
                } footer: {
                    Text("Higher resolutions and frame rates depend on the device. Detection must keep up to reach the chosen rate.")
                }

                if !photoSizes.isEmpty {
                    Section {
                        Picker("Photo size", selection: photoSizeSelection) {
                            ForEach(photoSizes) { format in
                                Text(format.label).tag(format.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("Capture")
                    } footer: {
                        Text("Tap the live view to capture a still at this resolution, then tune detection against the frozen image. Larger sizes give the detector more detail to work with via quad decimate.")
                    }
                }

                Section {
                    sliderRow(title: "Threads",
                              value: $settings.threads,
                              range: 1...8, step: 1,
                              format: "%.0f")
                    sliderRow(title: "Quad decimate",
                              value: $settings.quadDecimate,
                              range: 1...4, step: 0.5,
                              format: "%.1f")
                    sliderRow(title: "Quad sigma",
                              value: $settings.quadSigma,
                              range: 0...2, step: 0.1,
                              format: "%.1f")
                    sliderRow(title: "Decode sharpening",
                              value: $settings.decodeSharpening,
                              range: 0...1, step: 0.05,
                              format: "%.2f")
                    Toggle("Refine edges", isOn: $settings.refineEdges)
                } header: {
                    Text("Detector")
                } footer: {
                    Text("Lower quad decimate detects smaller tags at the cost of speed. Quad sigma blurs the input to reduce noise.")
                }

                Section {
                    sliderRow(title: "Min cluster pixels",
                              value: $settings.minClusterPixels,
                              range: 5...200, step: 1,
                              format: "%.0f")
                    sliderRow(title: "Max corner candidates",
                              value: $settings.maxNumMaxima,
                              range: 1...20, step: 1,
                              format: "%.0f")
                    sliderRow(title: "Critical angle",
                              value: $settings.criticalAngleDegrees,
                              range: 0...45, step: 1,
                              format: "%.0f°")
                    sliderRow(title: "Max line fit MSE",
                              value: $settings.maxLineFitMSE,
                              range: 0...50, step: 0.5,
                              format: "%.1f")
                    sliderRow(title: "Min white/black diff",
                              value: $settings.minWhiteBlackDiff,
                              range: 0...100, step: 1,
                              format: "%.0f")
                    Toggle("Deglitch", isOn: $settings.deglitch)
                } header: {
                    Text("Quad threshold")
                } footer: {
                    Text("Controls how candidate quads are found and rejected. Critical angle of 0 rejects no quads; deglitch only helps very noisy images.")
                }

                Section {
                    ForEach(TagFamily.allCases) { family in
                        Toggle(family.displayName, isOn: Binding(
                            get: { settings.isEnabled(family) },
                            set: { settings.toggle(family, on: $0) }
                        ))
                    }
                } header: {
                    Text("Tag families")
                } footer: {
                    Text("Enable only the families you need — each active family adds detection work per frame.")
                }

                Section("Display") {
                    Toggle("Show FPS", isOn: $settings.showFPS)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The live format the picker currently reflects (selected, or the active
    /// one until the user chooses).
    private var effectiveFormatID: String {
        settings.selectedFormatID ?? camera.activeFormatID ?? ""
    }

    /// Still sizes the currently selected live format can capture.
    private var photoSizes: [CaptureFormat] {
        camera.photoSizesByFormatID[effectiveFormatID] ?? []
    }

    /// Reflects the user's choice, falling back to the camera's active format
    /// when nothing has been explicitly selected yet. Switching the live format
    /// re-defaults the photo size to that format's largest still.
    private var formatSelection: Binding<String> {
        Binding(
            get: { effectiveFormatID },
            set: { newID in
                settings.selectedFormatID = newID
                settings.selectedPhotoSizeID = camera.photoSizesByFormatID[newID]?.last?.id
            }
        )
    }

    /// Reflects the chosen still size, defaulting to the largest the selected
    /// live format supports when the saved choice no longer applies.
    private var photoSizeSelection: Binding<String> {
        Binding(
            get: {
                if let id = settings.selectedPhotoSizeID, photoSizes.contains(where: { $0.id == id }) {
                    return id
                }
                return photoSizes.last?.id ?? ""
            },
            set: { settings.selectedPhotoSizeID = $0 }
        )
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
