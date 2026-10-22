import Foundation
import AVFoundation

/// 负责把检测到的回合剪辑导出为视频文件。
struct RallyExporter {

    enum ExportError: Error {
        case noVideoTrack
        case exportFailed
    }

    /// 把所有回合拼接成一个「高光合集」视频（含原音轨）。
    /// - Parameters:
    ///   - asset: 原始视频
    ///   - rallies: 检测到的回合
    ///   - url: 输出文件路径（建议 .mp4）
    func exportHighlights(asset: AVAsset,
                          rallies: [Rally],
                          to url: URL,
                          progress: @escaping (Double) -> Void,
                          completion: @escaping (Result<URL, Error>) -> Void) {
        let composition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(.failure(ExportError.noVideoTrack))
            return
        }
        let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = asset.tracks(withMediaType: .audio).first
        let compAudio: AVMutableCompositionTrack? = audioTrack == nil ? nil :
            composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        do {
            for rally in rallies {
                let range = rally.timeRange
                try compVideo?.insertTimeRange(range, of: videoTrack, at: cursor)
                if let compAudio, let audioTrack {
                    try compAudio.insertTimeRange(range, of: audioTrack, at: cursor)
                }
                cursor = CMTimeAdd(cursor, range.duration)
            }
        } catch {
            completion(.failure(error))
            return
        }

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(.failure(ExportError.exportFailed))
            return
        }
        session.outputURL = url
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            progress(Double(session.progress))
            if session.status != .exporting { t.invalidate() }
        }
        RunLoop.main.add(progressTimer, forMode: .common)

        session.exportAsynchronously {
            progressTimer.invalidate()
            switch session.status {
            case .completed:
                completion(.success(url))
            default:
                completion(.failure(session.error ?? ExportError.exportFailed))
            }
        }
    }

    /// 导出单个回合为独立片段。
    func exportRally(asset: AVAsset,
                     rally: Rally,
                     to url: URL,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality
        ) else {
            completion(.failure(ExportError.exportFailed))
            return
        }
        session.timeRange = rally.timeRange
        session.outputURL = url
        session.outputFileType = .mp4
        session.exportAsynchronously {
            switch session.status {
            case .completed:
                completion(.success(url))
            default:
                completion(.failure(session.error ?? ExportError.exportFailed))
            }
        }
    }
}
