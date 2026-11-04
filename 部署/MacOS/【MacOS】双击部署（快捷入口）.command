#!/bin/zsh
# 脚本自述：MacOS 部署快捷入口，仅转交包内脚本；复用其自述、确认和参数。
SCRIPT_ENTRY="$0"

main() {
  local shortcut_dir shortcut_target
  shortcut_dir="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_ENTRY")" && pwd -P)" || return 1
  shortcut_target="$shortcut_dir/【MacOS】部署.command/【MacOS】部署.command"
  if [ ! -f "$shortcut_target" ]; then
    printf '%s\n' "找不到部署脚本：$shortcut_target；请保留快捷入口与同名脚本包的相对位置。" >&2
    return 1
  fi
  exec /bin/zsh "$shortcut_target" "$@"
}

main "$@"
