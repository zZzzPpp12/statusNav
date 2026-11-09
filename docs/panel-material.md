# 面板材质与布局

本文记录 StatusNav 面板的材质层级、尺寸反馈与验证方式。

StatusNav 的面板由透明 NSPanel、PanelSurfaceView、系统材质、普通内容容器和滚动视口组成。macOS 26 使用标准 NSGlassEffectView；更早版本使用 NSVisualEffectView 的 popover 材质。根容器统一裁剪圆角，内容不绘制底色。系统“降低透明度”仍由原生材质处理。

SwiftUI 的内容高度可能晚于 ObservableObject 的通知更新。PanelView 通过 GeometryReader 和 PreferenceKey 回报完整内容的实际尺寸，下一轮主线程更新窗口大小，避免把旧的 fittingSize 当作最终高度。尺寸相同的布局不重复触发窗口更新。

运行 `StatusNav --smoke-test` 检查实际文档、视口和窗口尺寸，以及长提示出现、消失时的高度和顶部锚点。自检等待正常布局通知收敛，超时失败；不会在等待过程中反复强制刷新来掩盖丢失的布局通知。

`--preview-directory` 导出的是透明的 SwiftUI 内容图，包含文字和控件，不包含 WindowServer 合成的背景模糊。它只能用于检查排版，不能据此判断屏幕上的玻璃透明程度。
