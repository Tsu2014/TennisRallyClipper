import Foundation
import CoreMedia

/// 一个检测到的网球回合（一段连续击球的时间区间）。
struct Rally: Identifiable, Equatable {
    let id = UUID()
    /// 序号（从 0 开始）
    let index: Int
    /// 起始时间（秒）
    let startTime: Double
    /// 结束时间（秒）
    let endTime: Double
    /// 置信度（0...1），由该段运动能量高于阈值的比例估算
    let confidence: Double

    /// 对应到 CoreMedia 的时间区间
    var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: max(endTime - startTime, 0), preferredTimescale: 600)
        )
    }

    var duration: Double { endTime - startTime }
}
