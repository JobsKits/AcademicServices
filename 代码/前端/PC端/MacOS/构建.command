#!/bin/zsh
set -euo pipefail
readonly SCRIPT_DIR="${0:A:h}"
show_intro() {
  print '知序 MacOS 原生客户端构建：使用本机 Swift 编译，读取相邻 Web 素材与原有许可字体，写入本工程 Dist，不安装依赖、不改系统配置。'
  if [[ "${1:-}" != '--build' ]]; then
    [[ -t 0 ]] || { print -u2 '非交互构建请使用 --build'; return 1; }
    local answer=''
    read -r 'answer?按回车构建，输入其它内容取消：'
    [[ -z "$answer" ]] || return 1
  fi
}
build_app() {
  local bundle="$SCRIPT_DIR/Dist/知序.app"
  [[ ! -L "$SCRIPT_DIR/Dist" && ! -L "$bundle" ]] || { print -u2 '拒绝符号链接输出'; return 1; }
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
  xcrun swiftc -parse-as-library -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" "$SCRIPT_DIR"/Sources/*.swift -o "$bundle/Contents/MacOS/Zhixu"
  cp "$SCRIPT_DIR/Info.plist" "$bundle/Contents/Info.plist"
  cp -R "$SCRIPT_DIR/../Web/Assets/." "$bundle/Contents/Resources/"
  (
    cd "$SCRIPT_DIR"
    /usr/bin/shasum -a 256 Sources/*.swift Info.plist
  ) > "$bundle/Contents/Resources/SourceManifest.sha256"
  (
    cd "$SCRIPT_DIR/../Web/Assets"
    /usr/bin/shasum -a 256 -- **/*(.)
  ) > "$bundle/Contents/Resources/ResourceManifest.sha256"
  /usr/bin/codesign --force --sign - "$bundle"
  /usr/bin/codesign --verify --deep --strict "$bundle"
  print "构建完成：$bundle"
}
main() {
  show_intro "${1:-}"
  build_app
}
main "$@"
