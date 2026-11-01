#!/bin/zsh
# 脚本自述：准备知序工程私有运行环境并执行run；构建会清理本应用dist旧包。
# 仅写工程内目录，不改全局PATH；先自述回车，Ctrl+C或非空输入取消。
SCRIPT_DIR="${0:A:h}"
PROJECT="${SCRIPT_DIR}/zhixu"
run="run"
PYTHON=""
LOG_FILE="${PROJECT}/.build/session.log"
# 显示影响范围并等待本次操作确认。
show_script_intro_and_wait() {
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        print -P '%B%F{red}知序桌面端 · MacOS%f%b'
        print -P '%F{blue}运行模式：'"${run}"'。仅在工程内准备环境；不修改系统PATH。%f'
    else
        print -r -- "知序桌面端 · MacOS；模式：${run}"
    fi
    print -r -- "构建会清理本应用 dist 内旧包，生成APP+DMG；成功后定位产物并启动本次软件。"
    print -r -- "缺少Python时，下载官方uv并校验SHA256，在工程.tools内取得Python3.15.2。"
    print -r -- "来源：https://github.com/astral-sh/uv/releases/tag/0.13.6；依赖：https://pypi.org/"
    print -r -- "日志：${LOG_FILE}；Ctrl+C取消。"
    local answer=""
    [[ -t 0 ]] || { print -u2 '没有交互输入，请双击入口或在终端中运行。'; exit 1; }
    IFS= read -r 'answer?已了解用途与影响，直接回车继续；任意字符取消：' || exit 1
    [[ -z "$answer" ]] || exit 1
}
# 确认后准备日志与严格失败传播。
initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL ERR_EXIT
    export ZHIXU_ENTRY_LOGGING=1
    mkdir -p "${PROJECT}/.build"
}
# 仅缺少可用Python时准备项目私有运行时。
ensure_python() {
    local candidate="$(command -v python3 || true)"
    if [[ -n "$candidate" ]] && "$candidate" -c 'import sys; assert (3,10) <= sys.version_info[:2] < (3,16)' 2>/dev/null; then
        PYTHON="$candidate"
        return
    fi
    local answer=""
    IFS= read -r 'answer?缺少可用Python；直接回车下载到本工程，任意字符取消：' || exit 1
    [[ -z "$answer" ]] || exit 1
    local arch="$(uname -m)"
    [[ "$arch" == arm64 ]] && arch=aarch64
    [[ "$arch" == aarch64 || "$arch" == x86_64 ]] || { print -u2 '不支持该CPU架构'; exit 1; }
    local tools="${PROJECT}/.tools"
    local asset="uv-${arch}-apple-darwin.tar.gz"
    local source="https://github.com/astral-sh/uv/releases/download/0.13.6/${asset}"
    mkdir -p "$tools"
    print -r -- "来源：${source} → ${tools}"
    curl -fL --retry 2 "$source" -o "${tools}/${asset}"
    curl -fL --retry 2 "${source}.sha256" -o "${tools}/${asset}.sha256"
    local expected="$(awk '{print $1}' "${tools}/${asset}.sha256")"
    local actual="$(shasum -a 256 "${tools}/${asset}" | awk '{print $1}')"
    [[ ${#expected} == 64 && "$expected" == "$actual" ]] || { print -u2 'uv校验失败'; exit 1; }
    tar -xzf "${tools}/${asset}" -C "$tools"
    local uv="${tools}/uv-${arch}-apple-darwin/uv"
    "$uv" --version
    export UV_PYTHON_INSTALL_DIR="${tools}/python"
    "$uv" python install 3.15.2
    PYTHON="$("$uv" python find --managed-python 3.15.2)"
    "$PYTHON" -c 'import sys; assert (3,10) <= sys.version_info[:2] < (3,16)'
}
# 交给工程内构建器完成依赖复检、运行或本机打包。
run_application() {
    "$PYTHON" "${PROJECT}/scripts/manage.py" "$run" --entry-confirmed 2>&1 | tee "$LOG_FILE"
}
# 编排本次确认、环境与业务流程。
main() {
    show_script_intro_and_wait # 先说明影响范围并确认本次操作。
    initialize_runtime # 确认后准备工程内日志与失败传播。
    ensure_python # 缺少运行时才下载到工程私有目录并复检。
    run_application # 执行源码运行或本机打包，保留完整日志。
}
main "$@"
