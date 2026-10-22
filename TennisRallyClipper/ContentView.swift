import SwiftUI
import AVFoundation
import Photos
import CoreMedia

/// 串联「选视频 → 分析 → 检测回合 → 导出」的状态机。
final class EditorModel: ObservableObject {
    @Published var asset: AVAsset?
    @Published var player: AVPlayer?
    @Published var rallies: [Rally] = []
    @Published var analysisProgress: Double = 0
    @Published var isAnalyzing = false
    @Published var isExporting = false
    @Published var statusMessage = "选择一个网球视频开始"

    private let analyzer = MotionAnalyzer()
    private let detector = RallyDetector()
    private let exporter = RallyExporter()

    /// 用户从相册选好视频后调用。
    func pick(url: URL) {
        let asset = AVAsset(url: url)
        self.asset = asset
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        analyze(asset: asset)
    }

    private func analyze(asset: AVAsset) {
        isAnalyzing = true
        analysisProgress = 0
        statusMessage = "分析中…"
        rallies = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let samples = try analyzer.analyze(
                    asset: asset,
                    progress: { p in DispatchQueue.main.async { self.analysisProgress = p } },
                    cancellation: { false }
                )
                let duration = CMTimeGetSeconds(asset.duration)
                let rallies = detector.detect(samples: samples, videoDuration: duration)
                DispatchQueue.main.async {
                    self.rallies = rallies
                    self.isAnalyzing = false
                    self.statusMessage = rallies.isEmpty
                        ? "未检测到明显回合，可调整灵敏度后重试"
                        : "检测到 \(rallies.count) 个回合"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAnalyzing = false
                    self.statusMessage = "分析失败：\(error.localizedDescription)"
                }
            }
        }
    }

    /// 导出所有回合拼接的高光合集。
    func exportHighlights(to url: URL,
                          completion: @escaping (Result<URL, Error>) -> Void) {
        guard let asset else {
            completion(.failure(NSError(domain: "EditorModel", code: -1,
                                         userInfo: [NSLocalizedDescriptionKey: "没有视频"])))
            return
        }
        isExporting = true
        exporter.exportHighlights(asset: asset, rallies: rallies, to: url,
                                  progress: { _ in }) { result in
            DispatchQueue.main.async { self.isExporting = false }
            completion(result)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = EditorModel()
    @State private var showPicker = false
    @State private var exportedURL: URL?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player = model.player {
                    PlayerView(player: player)
                        .frame(height: 260)
                        .background(Color.black)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 260)
                        .overlay(Text("未选择视频").foregroundColor(.secondary))
                        .padding(.horizontal)
                }

                if model.isAnalyzing {
                    ProgressView("分析回合中…", value: model.analysisProgress)
                        .padding(.horizontal)
                } else {
                    Text(model.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                if !model.rallies.isEmpty {
                    List {
                        Section(header: Text("检测到的回合（\(model.rallies.count)）")) {
                            ForEach(model.rallies) { rally in
                                RallyRow(rally: rally) {
                                    seek(to: rally.startTime)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("选择视频", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if !model.rallies.isEmpty {
                        Button {
                            exportHighlights()
                        } label: {
                            Label("导出高光", systemImage: "scissors")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isExporting)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("网球回合剪辑")
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    model.pick(url: url)
                }
            }
            .sheet(isPresented: Binding(
                get: { exportedURL != nil },
                set: { if !$0 { exportedURL = nil } }
            )) {
                if let url = exportedURL {
                    VStack(spacing: 16) {
                        ShareSheet(items: [url])
                            .frame(maxHeight: 420)
                        Button {
                            saveToPhotos(url)
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("关闭") { exportedURL = nil }
                    }
                    .padding()
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好") { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func seek(to time: Double) {
        model.player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }

    private func exportHighlights() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("高光合集_\(Int(Date().timeIntervalSince1970)).mp4")
        model.exportHighlights(to: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let u):
                    exportedURL = u
                case .failure(let e):
                    alertMessage = "导出失败：\(e.localizedDescription)"
                }
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    alertMessage = "未获得相册写入权限"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                DispatchQueue.main.async {
                    alertMessage = success ? "已保存到相册" : "保存失败"
                }
            }
        }
    }
}
