#!/bin/zsh
# 脚本自述：反部署快捷入口，只定位并转交唯一实施脚本；复用内层自述和确认。
SCRIPT_ENTRY="$0"
# 按快捷文件自身位置转交，保留参数和退出码。
dispatch_undeployment() {
  local shortcut_dir shortcut_target
  shortcut_dir="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_ENTRY")" && pwd -P)" || return 1
  shortcut_target="$shortcut_dir/【MacOS】反部署.command/【MacOS】反部署.command"
  [ -f "$shortcut_target" ] && [ ! -L "$shortcut_target" ] || { printf '%s\n' "缺少反部署脚本：$shortcut_target" >&2; return 1; }
  exec /bin/zsh "$shortcut_target" "$@"
}
# 快捷文件不另建部署逻辑或额外确认。
main() {
  dispatch_undeployment "$@" # 运行包内唯一实现并原样传递结果。
}
main "$@"
