//
//  ClothingCameraPicker.swift
//  Haki
//
//  The system camera (UIImagePickerController) for photographing a piece of
//  clothing. Present it with `.fullScreenCover` and only when
//  `ClothingCameraPicker.isAvailable` (there's no camera in the Simulator).
//

import Foundation
import SwiftUI
import UIKit

struct ClothingCameraPicker: UIViewControllerRepresentable {
    /// Called with the photo that was taken.
    let onImage: (UIImage) -> Void
    /// Called when the person closes the camera without a photo.
    let onCancel: () -> Void

    init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.onImage = onImage
        self.onCancel = onCancel
    }

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onImage = onImage
        context.coordinator.onCancel = onCancel
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        var onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

#Preview {
    // The Simulator has no camera, so this shows the photo library instead.
    ClothingCameraPicker(onImage: { _ in }, onCancel: {})
        .ignoresSafeArea()
        .previewEnvironment()
}
