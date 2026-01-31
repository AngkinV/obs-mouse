# OBS Mouse Zoom (Enhanced) v3.1

一个优化版的 OBS Lua 脚本，用于在录制/直播时跟随鼠标放大画面内容。

基于 [obs-zoom-to-mouse](https://github.com/BlankSourceCode/obs-zoom-to-mouse) 进行优化，**修复了 macOS 兼容性问题**。

## 主要改进

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

### 🆕 放大镜特效 (v3.1 新增)
- **自动生成**: 无需外部素材，脚本自动生成放大镜图形
- **放大镜内容**: 放大镜区域实时显示鼠标位置的放大内容
- **动漫入场动画**: 放大镜从画面边缘滑入，带有回弹效果
- **平滑跟随**: 放大镜跟随鼠标移动，始终对准鼠标位置
- **可自定义**: 支持调整缩放比例、放大倍数、入场方向等

### 视觉特效 (v3.0)
- **聚焦效果 (Vignette)**: 放大时自动增强对比度和饱和度，产生电影感的聚焦效果
- **鼠标聚光灯 (Spotlight)**: 放大时鼠标周围保持明亮，其余区域变暗，突出鼠标位置
- 可通过快捷键单独开关聚光灯效果
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
2. 搜索 "zoom"
3. 为以下操作设置快捷键：
   - **Toggle zoom to mouse** - 开启/关闭缩放
   - **Toggle follow mouse during zoom** - 开启/关闭鼠标跟随
   - **Toggle spotlight during zoom** - 开启/关闭聚光灯效果 (v3.0 新增)

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
| **Enable mouse spotlight** | 启用鼠标聚光灯 | 开启 |
| Spotlight radius | 聚光灯半径 (像素) | 200 |
| Spotlight darkness | 周围区域暗度 | 0.4 |
| **Enable magnifier character** | 启用放大镜角色 | 开启 |
| Character scale | 角色缩放比例 | 0.5 |
| Magnifier zoom | 放大镜内放大倍数 | 2.5 |
| Entry direction | 角色入场方向 | From Right |

## 动画风格对比

- **Smooth**：平滑渐进，专业感强（推荐）
- **Elastic**：弹性效果，有回弹感
- **Bounce**：弹跳效果，活泼有趣

## 放大镜效果说明

放大镜效果**无需外部素材**，脚本运行时会自动生成：
- 带有金属边框和手柄的放大镜图形
- 用于圆形裁剪的遮罩图像

生成的 TGA 文件会保存在脚本目录下（`magnifier_frame.tga` 和 `magnifier_mask.tga`）。

高级设置中可调整放大镜位置参数以适应不同的使用场景。

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

### v3.1
- 新增放大镜特效 - 自动生成放大镜图形，无需外部素材
- 放大镜区域实时显示放大内容，带有金属边框和手柄
- 动漫风格入场/退场动画（滑入 + 弹跳 + 弹性效果）
- 支持自定义入场方向、缩放比例、放大倍数
- 高级设置支持调整放大镜位置参数

### v3.0
- 新增聚焦效果 (Vignette) - 放大时增强对比度和饱和度
- 新增鼠标聚光灯效果 (Spotlight) - 鼠标周围明亮，周围区域变暗
- 新增聚光灯开关快捷键
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
