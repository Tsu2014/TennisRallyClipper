import Foundation
import AVFoundation
import CoreMedia
import Accelerate

/// 单帧的运动能量采样点。
struct MotionSample {
    /// 该帧对应的时间（秒）
    let time: Double
    /// 该帧相对前一帧的平均运动位移（光流块匹配幅度）
    let energy: Double
}

/// 基于「块匹配光流」的运动分析器。
///
/// 思路：用 `AVAssetReader` 逐帧读取视频的亮度(Y)平面，降采样后，
/// 对相邻两帧做分块(block)匹配，估计每块的平均位移，把所有块的平均位移
/// 作为该时刻的「运动能量」。网球回合内画面运动剧烈，能量会明显抬升，
/// 回合间（捡球、走位）能量回落，因此可用能量曲线切割回合。
struct MotionAnalyzer {

    /// 采样间隔（秒）。越小越精确但越慢。默认约 10fps。
    let sampleInterval: Double
    /// 降采样后的宽度（像素）。高度按比例计算。越大越精确越慢。
    let downscaleWidth: Int
    /// 匹配块边长（像素，降采样空间）
    let blockSize: Int
    /// 块匹配搜索半径（像素）
    let searchRadius: Int

    init(sampleInterval: Double = 0.1,
         downscaleWidth: Int = 64,
         blockSize: Int = 8,
         searchRadius: Int = 4) {
        self.sampleInterval = sampleInterval
        self.downscaleWidth = downscaleWidth
        self.blockSize = blockSize
        self.searchRadius = searchRadius
    }

    enum AnalysisError: Error {
        case noVideoTrack
        case cannotAccessPixelBuffer
    }

    /// 分析视频，返回按时间排序的运动能量序列。
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - progress: 进度回调（0...1），主线程调用
    ///   - cancellation: 取消判定，返回 true 时中止
    func analyze(asset: AVAsset,
                 progress: @escaping (Double) -> Void,
                 cancellation: @escaping () -> Bool) throws -> [MotionSample] {
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw AnalysisError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw AnalysisError.noVideoTrack
        }

        let duration = CMTimeGetSeconds(asset.duration)
        var samples: [MotionSample] = []
        var prev: (data: Data, width: Int, height: Int)? = nil
        var lastSampleTime = -1.0

        while let buffer = output.copyNextSampleBuffer() {
            if cancellation() {
                reader.cancelReading()
                return samples
            }
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            if time - lastSampleTime < sampleInterval - 1e-6, prev != nil {
                CMSampleBufferInvalidate(buffer)
                continue
            }
            lastSampleTime = time

            guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
                CMSampleBufferInvalidate(buffer)
                continue
            }
            let luma: (data: Data, width: Int, height: Int)
            do {
                luma = try downsampleLuma(imageBuffer)
            } catch {
                CMSampleBufferInvalidate(buffer)
                continue
            }

            if let p = prev {
                let energy = blockMatchMotion(
                    prev: p.data, prevW: p.width, prevH: p.height,
                    curr: luma.data, currW: luma.width, currH: luma.height,
                    blockSize: blockSize, radius: searchRadius
                )
                samples.append(MotionSample(time: time, energy: energy))
            }
            prev = luma
            CMSampleBufferInvalidate(buffer)
            if duration > 0 { progress(min(time / duration, 1.0)) }
        }
        reader.cancelReading()
        return samples
    }

    // MARK: - 亮度降采样

    private func downsampleLuma(_ buffer: CVImageBuffer) throws
        -> (data: Data, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let fullW = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let fullH = CVPixelBufferGetHeightOfPlane(buffer, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else {
            throw AnalysisError.cannotAccessPixelBuffer
        }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

        var src = vImage_Buffer(
            data: base,
            height: vImagePixelCount(fullH),
            width: vImagePixelCount(fullW),
            rowBytes: rowBytes
        )

        let scale = Double(downscaleWidth) / Double(fullW)
        let outW = downscaleWidth
        let outH = max(1, Int(Double(fullH) * scale))

        var outData = Data(count: outW * outH)
        outData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            var dst = vImage_Buffer(
                data: baseAddress,
                height: vImagePixelCount(outH),
                width: vImagePixelCount(outW),
                rowBytes: outW
            )
            vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
        }
        return (outData, outW, outH)
    }

    // MARK: - 块匹配光流

    private func blockMatchMotion(prev: Data, prevW: Int, prevH: Int,
                                  curr: Data, currW: Int, currH: Int,
                                  blockSize: Int, radius: Int) -> Double {
        guard prevW == currW, prevH == currH else {
            return frameDifference(prev: prev, curr: curr)
        }
        let w = prevW, h = prevH
        var total: Double = 0
        var count = 0

        for by in stride(from: 0, to: h - blockSize, by: blockSize) {
            for bx in stride(from: 0, to: w - blockSize, by: blockSize) {
                let minX = max(0, bx - radius)
                let maxX = min(w - blockSize, bx + radius)
                let minY = max(0, by - radius)
                let maxY = min(h - blockSize, by + radius)

                var best = Double.greatestFiniteMagnitude
                var bestDx = 0, bestDy = 0
                for cy in minY...maxY {
                    for cx in minX...maxX {
                        let sad = sumAbsDiff(prev: prev, curr: curr, w: w,
                                            bx: bx, by: by, cx: cx, cy: cy, bs: blockSize)
                        if sad < best {
                            best = sad
                            bestDx = cx - bx
                            bestDy = cy - by
                        }
                    }
                }
                total += sqrt(Double(bestDx * bestDx + bestDy * bestDy))
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    private func sumAbsDiff(prev: Data, curr: Data, w: Int,
                            bx: Int, by: Int, cx: Int, cy: Int, bs: Int) -> Double {
        var sum = 0
        for y in 0..<bs {
            let pRow = (by + y) * w + bx
            let cRow = (cy + y) * w + cx
            for x in 0..<bs {
                sum += abs(Int(prev[pRow + x]) - Int(curr[cRow + x]))
            }
        }
        return Double(sum)
    }

    private func frameDifference(prev: Data, curr: Data) -> Double {
        let n = min(prev.count, curr.count)
        guard n > 0 else { return 0 }
        var sum = 0
        for i in 0..<n { sum += abs(Int(prev[i]) - Int(curr[i])) }
        return Double(sum) / Double(n)
    }
}
