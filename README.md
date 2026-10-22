# TennisRallyClipper

从 iPhone 相册选择一段网球视频，**自动检测打球回合**并剪辑成「高光合集」。

- 选视频：基于系统 `PHPicker`，无需相册授权即可选取。
- 回合检测：基于**块匹配光流**（Block-Matching Optical Flow）分析画面运动能量，
  回合内运动剧烈、回合间（捡球/走位）能量回落，据此自动切分回合。
- 剪辑导出：用 `AVFoundation` 把检测到的回合无缝拼接成一个高光视频，
  可分享或保存到相册。

## 运行方式

1. 需要 **macOS + Xcode 15+**（本工程用 Xcode 工程格式，非 SwiftPM）。
2. 用 Xcode 打开 `TennisRallyClipper.xcodeproj`。
3. 选中 TARGET → Signing & Capabilities，设置自己的 **Team** 和 **Bundle Identifier**
   （默认 `com.example.TennisRallyClipper` 需改成你自己的）。
4. 连接真机（相册选取视频建议在真机体验；模拟器可在 `Photos` 里先同步一个视频，
   或把视频文件直接拖进模拟器）。
5. `Cmd + R` 运行。

> 注意：保存剪辑结果到相册需要 `NSPhotoLibraryAddUsageDescription` 授权，
> 已在工程配置中预置。

## 原理简述

- `Analysis/MotionAnalyzer.swift`：逐帧读取亮度(Y)平面 → 降采样 → 相邻帧分块匹配，
  估计平均位移作为「运动能量」时间序列。
- `Analysis/RallyDetector.swift`：对能量序列平滑、取中位数做阈值，
  提取活跃段 → 合并过近间隔 → 过滤过短片段 → 加边界缓冲，得到回合区间。
- `Export/RallyExporter.swift`：`AVMutableComposition` 拼接所有回合（保留音轨），
  用 `AVAssetExportSession` 导出为 MP4。

## 可调参数

- `RallyDetectorConfig`：`sensitivity`（灵敏度）、`mergeGap`（合并间隔）、
  `minRallyDuration`（最短回合）、`margin`（边界缓冲）。
- `MotionAnalyzer` 初始化参数：`sampleInterval`（采样间隔）、`downscaleWidth`、
  `blockSize`、`searchRadius`（精度/速度权衡）。

## 工程结构

```
TennisRallyClipper/
├── TennisRallyClipperApp.swift      # App 入口
├── ContentView.swift                # 主界面 + 编排逻辑(EditorModel)
├── Views/
│   ├── VideoPicker.swift            # 相册选视频
│   ├── PlayerView.swift             # 视频播放
│   ├── RallyListView.swift          # 回合列表行
│   └── ShareSheet.swift             # 系统分享面板
├── Models/
│   └── Rally.swift                  # 回合模型
├── Analysis/
│   ├── MotionAnalyzer.swift         # 光流运动分析
│   └── RallyDetector.swift          # 回合检测聚类
└── Export/
    └── RallyExporter.swift          # 剪辑导出
```
