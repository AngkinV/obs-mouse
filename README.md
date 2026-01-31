# OBS Mouse Zoom (Enhanced) v4.0

一个优化版的 OBS Lua 脚本，用于在录制/直播时跟随鼠标放大画面内容。

基于 [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) 进行优化，**修复了 macOS 兼容性问题**。

## 主要改进

### 🆕 画中画系统 (v4.0 新增)
- **多窗口支持**: 最多同时显示 3 个独立的画中画放大窗口
- **每个窗口展示不同内容**: 通过偏移量设置，每个窗口可以显示鼠标周围不同区域的放大内容
- **3 种窗口模式**:
  - **跟随鼠标**: 实时显示鼠标位置附近的放大内容，支持 X/Y 偏移量让每个窗口显示不同区域
  - **固定区域**: 监控屏幕上指定坐标的固定区域
  - **锁定位置**: 锁定在当前鼠标位置
- **8 种预设位置**: 左上、上中、右上、左中、右中、左下、下中、右下
- **独立设置**: 每个窗口可单独设置放大倍率、显示大小、偏移量
- **圆角边框**: 自动生成白色圆角边框装饰
- **平滑跟随**: 窗口内容平滑跟随鼠标移动
- **快捷键支持**: 可独立切换/锁定每个窗口，或一键切换全部

### 角色叠加效果 (Character Overlay)
- **可爱角色**: 放大时在鼠标位置显示自定义角色图片 (Cute.png)
- **动漫入场动画**: 角色从画面边缘滑入，带有回弹效果
- **平滑跟随**: 角色跟随鼠标移动
- **可自定义锚点**: 设置角色与鼠标的对齐位置
- **可调整大小**: 支持缩放角色显示比例

### macOS 兼容性修复
- 使用 `CGEventGetLocation` API 替代原来的 `NSEvent.mouseLocation`（更可靠）
- 添加多种备用方法，自动选择可用的 API
- 更好的错误提示和状态反馈
- 支持 OBS 31+ 新版 Transform API

### 现代化动画效果
- 新增 **Smootherstep** 缓动函数（更平滑的动画）
- 支持 **弹性(Elastic)** 动画效果
- 支持 **弹跳(Bounce)** 动画效果
- 可在设置中选择动画风格

### 视觉特效
- **聚焦效果 (Vignette)**: 放大时自动增强对比度和饱和度，产生电影感的聚焦效果
- 所有特效仅在放大时激活，缩小后自动移除

### 用户体验优化
- 脚本描述直接显示 API 状态
- 更清晰的设置界面分组
- 更好的默认参数值
- 完善的错误处理和日志输出

## 安装方法

1. 打开 OBS Studio
2. 菜单栏 → **工具** → **脚本**
3. 点击 **+** 按钮
4. 选择 `obs-mouse-zoom.lua` 文件
5. 脚本加载后会自动显示 API 状态

## 使用方法

### 基础设置

1. 在脚本设置中选择 **Zoom Source**（选择你的显示器捕获源）
2. 设置 **Zoom Factor**（缩放倍数，推荐 2-4）
3. 设置 **Zoom Speed**（缩放速度，推荐 0.08）

### 设置快捷键

1. 进入 **设置** → **快捷键**
2. 搜索 "zoom" 或 "pip"
3. 为以下操作设置快捷键：
   - **Toggle zoom to mouse** - 开启/关闭缩放
   - **Toggle follow mouse during zoom** - 开启/关闭鼠标跟随
   - **Toggle spotlight during zoom** - 开启/关闭聚光灯效果
   - **Toggle PiP Window 1/2/3** - 开启/关闭单个画中画窗口
   - **Lock PiP Window 1/2/3** - 锁定/解锁画中画窗口位置
   - **Toggle All PiP Windows** - 一键切换全部画中画窗口

### macOS 特别说明

如果脚本显示 "API NOT Available"：

1. **授予辅助功能权限**
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能
   - 添加 OBS Studio 到允许列表

2. **手动配置显示器参数**
   - 勾选 "Set manual source position"
   - 设置你的显示器分辨率（如 1920x1080 或 2560x1440）
   - X/Y 设为 0（主显示器）

## 设置参数说明

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| Zoom Factor | 放大倍数 | 2-4 |
| Zoom Speed | 缩放动画速度 | 0.08 |
| Auto follow mouse | 自动跟随鼠标 | 开启 |
| Follow Speed | 跟随速度 | 0.15 |
| Follow Border | 触发跟随的边缘距离 | 8 |
| Lock Sensitivity | 锁定灵敏度 | 6 |
| Use smooth modern easing | 使用现代平滑动画 | 开启 |
| Easing Style | 动画风格 | Smooth |
| **Enable focus effect** | 启用聚焦效果 | 开启 |
| Focus effect intensity | 聚焦效果强度 | 0.5 |
| **Enable character overlay** | 启用角色叠加 | 开启 |
| Character scale | 角色缩放比例 | 0.5 |
| Anchor X/Y (%) | 角色锚点位置 | 0 |
| Entry direction | 角色入场方向 | From Right |
| **Enable Picture-in-Picture** | 启用画中画系统 | 关闭 |
| Enable Window 1/2/3 | 启用对应画中画窗口 | 窗口1开启 |
| Mode | 窗口模式 (跟随/固定/锁定) | Follow Mouse |
| Display Position | 窗口显示位置 | Top Right |
| Zoom Factor (PiP) | 画中画放大倍率 | 2.5 |
| Display Width/Height | 画中画窗口大小 | 320x240 |
| Offset X/Y | 跟随模式下的位置偏移量 | 窗口1: 0,0 / 窗口2: 500,0 / 窗口3: 0,500 |
| Source X/Y | 固定区域模式下的源坐标 | 0, 0 |
| Show Border | 显示圆角边框 | 开启 |

## 动画风格对比

- **Smooth**：平滑渐进，专业感强（推荐）
- **Elastic**：弹性效果，有回弹感
- **Bounce**：弹跳效果，活泼有趣


## 故障排除

### 问题：脚本加载报错
- 确保 OBS 版本 >= 28.0
- 检查 Lua 脚本是否完整

### 问题：鼠标位置不准确
1. 勾选 "Set manual source position"
2. 正确填写显示器的 X, Y, Width, Height
3. 多显示器时注意 X/Y 偏移

### 问题：缩放后画面撕裂
- 尝试降低 Zoom Speed
- 调整 Follow Speed

## 版本历史

### v4.0
- 新增画中画 (PiP) 系统
  - 放大时同时显示多个独立的放大窗口
  - 支持最多 3 个 PiP 窗口同时显示
  - **每个窗口可通过偏移量设置展示不同的区域内容**
  - 3 种窗口模式：跟随鼠标、固定区域、锁定位置
  - 8 种预设显示位置
  - 每个窗口独立设置放大倍率、显示大小、偏移量
  - 自动生成圆角白色边框装饰
  - 快捷键支持：切换/锁定单个窗口、一键切换全部
  - 平滑跟随动画
- 新增角色叠加效果 (Character Overlay)
  - 放大时在鼠标位置显示自定义角色图片 (Cute.png)
  - 动漫风格入场/退场动画
  - 可自定义锚点位置和缩放比例

### v3.0
- 新增聚焦效果 (Vignette) - 放大时增强对比度和饱和度
- 支持 OBS 31+ Transform API
- 优化场景切换时的效果清理
- 特效仅在放大时激活

### v2.0
- 修复 macOS API 兼容性问题
- 添加 CGEventGetLocation 支持
- 新增现代化动画效果
- 优化用户界面
- 改进错误处理

## 许可证

MIT License - 基于 BlankSourceCode 的原始项目优化
