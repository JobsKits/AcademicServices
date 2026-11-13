# 桌面账户体验验证

- `桌面反馈原生事件.json`：实际冻结 App 内运行的 Qt 事件验证，等待真实 4.5 秒定时器，再发出 `mousePress / mouseMove / mouseRelease` 检查拖动；没有直接调用切页方法。也核验游客设置、深浅主题主按钮、未登录个人页门禁与取消返回。
- `frozen-light.png`、`frozen-dark.png`：上述冻结 App 的实际原生页面截图。
- 桌面完整单测 74 项通过。另已用 CUA 读取实际 App 的自动切页与清楚的按钮文字；CUA 坐标点击／拖动对该 Qt 窗口返回 `noWindowsAvailable`，因此鼠标验证以冻结 App 的原生 Qt 事件结果为准，不标作 CUA 拖动通过。
- 范围为本机 MacOS Apple Silicon。Windows、其它设备、实体触控板手势不据此认定通过。
