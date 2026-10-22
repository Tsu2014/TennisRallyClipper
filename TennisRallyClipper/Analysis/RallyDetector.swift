import Foundation

/// 回合检测的可调参数。
struct RallyDetectorConfig {
    /// 灵敏度：阈值 = 能量中位数 × sensitivity。越大检测到的回合越少。
    var sensitivity: Double = 3.0
    /// 平滑窗口（采样点数）
    var smoothWindow: Int = 3
    /// 间隔小于该值（秒）的活跃段会被合并为同一回合
    var mergeGap: Double = 1.5
    /// 短于该值（秒）的片段会被丢弃（视为噪声）
    var minRallyDuration: Double = 1.0
    /// 每个回合前后补充的缓冲时间（秒）
    var margin: Double = 0.5
}

/// 把运动能量时间序列聚合成「回合」区间。
struct RallyDetector {

    let config: RallyDetectorConfig

    init(config: RallyDetectorConfig = RallyDetectorConfig()) {
        self.config = config
    }

    /// - Parameters:
    ///   - samples: 运动能量序列
    ///   - videoDuration: 视频总时长（秒），用于把首尾边界夹在区间内
    func detect(samples: [MotionSample], videoDuration: Double) -> [Rally] {
        guard samples.count > 1 else { return [] }

        let raw = samples.map { $0.energy }
        let energies = smooth(raw, window: config.smoothWindow)
        let median = medianOf(energies)
        let threshold = max(median * config.sensitivity, 1e-3)

        // 1. 提取活跃区间
        var intervals: [(start: Double, end: Double)] = []
        var curStart: Double? = nil
        for i in energies.indices {
            if energies[i] > threshold {
                if curStart == nil { curStart = samples[i].time }
            } else if let s = curStart {
                intervals.append((s, samples[i].time))
                curStart = nil
            }
        }
        if let s = curStart, let last = samples.last {
            intervals.append((s, last.time))
        }

        // 2. 合并过近的间隔
        var merged: [(Double, Double)] = []
        for iv in intervals {
            if let last = merged.last, iv.start - last.1 < config.mergeGap {
                merged[merged.count - 1] = (last.0, max(last.1, iv.end))
            } else {
                merged.append(iv)
            }
        }

        // 3. 过滤过短片段、补充缓冲、计算置信度
        var rallies: [Rally] = []
        var index = 0
        for iv in merged {
            let s = max(0, iv.0 - config.margin)
            let e = min(videoDuration, iv.1 + config.margin)
            guard e - s >= config.minRallyDuration else { continue }

            let segEnergies = samples.enumerated().compactMap { i, sm -> Double? in
                (sm.time >= s && sm.time <= e) ? energies[i] : nil
            }
            let peak = segEnergies.max() ?? threshold
            let conf = min(1.0, max(0, (peak - threshold) / max(threshold, 1e-6)))
            rallies.append(Rally(index: index, startTime: s, endTime: e, confidence: conf))
            index += 1
        }
        return rallies
    }

    // MARK: - 工具

    private func smooth(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > window else { return values }
        let half = window / 2
        var out: [Double] = []
        for i in values.indices {
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let sum = values[lo...hi].reduce(0, +)
            out.append(sum / Double(hi - lo + 1))
        }
        return out
    }

    private func medianOf(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
