import LakhasKit
import PhotosUI
import SwiftUI
import UIKit

/// One photo to pick from the library or take with the camera, with a preview. The raw data is
/// processed (downscaled, metadata stripped) by the caller before it's sent or saved.
struct PhotoSlot: View {
    let titleKey: LocalizedStringKey
    @Binding var data: Data?

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(titleKey).font(.subheadline.weight(.semibold))
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .accessibilityLabel(Text(titleKey))
            }
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("photo.library", systemImage: "photo.on.rectangle")
                }
                Spacer()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("photo.camera", systemImage: "camera")
                    }
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.Palette.primary)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let loaded = try? await item.loadTransferable(type: Data.self) { data = loaded }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { captured in
                if let captured { data = captured }
                showCamera = false
            }
            .ignoresSafeArea()
        }
    }
}
