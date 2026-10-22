import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 调用系统相册选择视频（PHPicker 不需要相册授权）。
struct VideoPicker: UIViewControllerRepresentable {
    /// 选中后回调一个本地临时文件 URL
    let onPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            let type = UTType.movie.identifier
            guard result.itemProvider.hasItemConformingToTypeIdentifier(type) else { return }
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { return }
                let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + ext)
                do {
                    if FileManager.default.fileExists(atPath: temp.path) {
                        try FileManager.default.removeItem(at: temp)
                    }
                    try FileManager.default.copyItem(at: url, to: temp)
                    DispatchQueue.main.async { self.onPicked(temp) }
                } catch {
                    // 忽略拷贝失败
                }
            }
        }
    }
}
