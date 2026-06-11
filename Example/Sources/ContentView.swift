import SwiftUI

/// Root view. The camera lives on the first page; swiping to the left reveals
/// the settings page (a horizontally paged `TabView`).
struct ContentView: View {
    @StateObject private var settings = DetectorSettings()
    @StateObject private var camera = CameraManager()

    private enum Page: Hashable { case camera, settings }
    @State private var page: Page = .camera

    var body: some View {
        TabView(selection: $page) {
            CameraScreen(camera: camera, showFPS: settings.showFPS)
                .tag(Page.camera)

            SettingsScreen(settings: settings, camera: camera)
                .tag(Page.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            camera.update(config: settings.config)
            camera.selectFormat(id: settings.selectedFormatID)
            camera.start()
        }
        .onChange(of: page) { _, newPage in
            // Apply edited settings only once the user returns to the camera.
            if newPage == .camera {
                camera.update(config: settings.config)
                camera.selectFormat(id: settings.selectedFormatID)
                settings.persist()
            }
        }
    }
}
