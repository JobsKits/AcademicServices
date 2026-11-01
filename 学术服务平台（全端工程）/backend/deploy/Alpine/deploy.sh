#!/bin/sh
# 脚本自述：
# - 在当前backend目录配置、准备Go、编译和运行知序服务；不改全局PATH或防火墙。
# - 首次保存管理员/客户密码；数据、日志和SDK留在本目录，Ctrl+C停止服务。
# - --check仅检查路径与平台，不下载、不写入；双击正常入口须回车确认。
SCRIPT_ENTRY="$0"
SERVER_ROOT=""
LOG_FILE=""
GO_EXE=""
TARGET_OS="linux"
PLATFORM_ID="Alpine"
GO_VERSION="go1.27.3"
# 按入口位置解析源码，不依赖终端工作目录。
prepare_display_context() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SCRIPT_ENTRY")" && pwd -P)" || exit 1
  SERVER_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)" || exit 1
  LOG_FILE="$SERVER_ROOT/.runtime/logs/deploy-$(date '+%Y%m%d-%H%M%S').log"
}
# 输出自述；确认前不写入磁盘。
show_script_intro_and_wait() {
  prepare_display_context
  printf '\n知序服务｜Alpine 部署\n'
  printf '%s\n' '1、配置本工程账户和监听地址，必要时下载官方Go SDK并校验SHA256。' '2、编译并在当前终端运行；Ctrl+C停止，不改全局PATH、系统服务或防火墙。' '3、仅本目录 .tools/.runtime/data 产生文件；已有配置与业务数据保留。' '4、Go模块默认使用goproxy.cn镜像，失败回退官方源；可用GOPROXY覆盖，仅当前进程生效。'
  printf '源码：%s\n日志：%s\n' "$SERVER_ROOT" "$LOG_FILE"
  if [ "${1:-}" = --check ]; then
    check_source
    check_platform
    printf '%s\n' '检查通过；尚未编译、安装或启动。'
    exit 0
  fi
  [ $# -eq 0 ] || { printf '%s\n' '不支持的参数。仅可使用 --check。' >&2; exit 2; }
  [ -t 0 ] || { printf '%s\n' '请在交互终端运行，未执行部署。' >&2; exit 1; }
  printf '%s' '按回车继续；输入任意字符取消：'
  IFS= read -r deploy_answer || exit 1
  [ -z "$deploy_answer" ] || exit 1
}
# 将进度写入本次日志。
log() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}
# 失败立即停止，保留日志和原数据。
fail() {
  log "失败：$*"
  exit 1
}
# 确认后才创建运行目录和日志。
initialize_runtime() {
  set -eu
  set -o pipefail
  umask 077
  for runtime_target in "$SERVER_ROOT/.runtime" "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/.tools" "$SERVER_ROOT/data"; do
    [ ! -L "$runtime_target" ] || { printf '%s\n' '拒绝写入符号链接运行目录。' >&2; exit 1; }
  done
  mkdir -p "$SERVER_ROOT/.runtime/logs" "$SERVER_ROOT/.runtime/bin" "$SERVER_ROOT/.tools" "$SERVER_ROOT/data"
  : > "$LOG_FILE"
  trap 'stty echo 2>/dev/null || true; printf "\n已停止；数据已保留。\n"; exit 130' INT TERM
}
# 拒绝缺少源码的半份拷贝。
check_source() {
  [ -f "$SERVER_ROOT/go.mod" ] && [ -d "$SERVER_ROOT/cmd/server" ] || { printf '%s\n' '请复制完整 backend 文件夹；缺少 go.mod 或 cmd/server。' >&2; exit 1; }
}
# 只读取系统发行标记，不执行os-release内容。
check_linux() {
  [ "$(uname -s)" = Linux ] || { printf '%s\n' '请使用当前系统专属入口。' >&2; exit 1; }
  distro_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '\"')"
  [ "$distro_id" = "$1" ] || { printf '当前发行版为%s，请使用对应入口。\n' "$distro_id" >&2; exit 1; }
}
# 检查目标系统，避免拿错平台入口。
check_platform() {
  check_linux alpine
}
# 必需依赖缺失时请求一次安装，非空输入和EOF均停止。
confirm_install() {
  printf '%s\n' "$1"
  printf '%s' '直接回车安装；输入任意字符后回车取消：'
  IFS= read -r dependency_answer || exit 1
  [ -z "$dependency_answer" ] || exit 1
}
# 检查下载与解压工具，只沿缺失分支安装。
ensure_transfer_tools() {
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && { command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || command -v sha256 >/dev/null 2>&1; }; then
    curl --version >/dev/null && tar --version >/dev/null 2>&1 && return 0
  fi
  confirm_install '缺少curl/tar/SHA256工具，将使用系统软件源安装基础工具；需要管理员权限。'
  log '来源｜系统已配置软件源｜apk 基础工具包'
  if [ "$(id -u)" -eq 0 ]; then sh -c 'apk add --no-cache ca-certificates curl tar coreutils' >> "$LOG_FILE" 2>&1 || fail '基础工具安装失败。'
  elif command -v sudo >/dev/null 2>&1; then sudo sh -c 'apk add --no-cache ca-certificates curl tar coreutils' >> "$LOG_FILE" 2>&1 || fail '基础工具安装失败。'
  else fail '需要root或sudo安装基础工具。'; fi
  command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || fail '工具安装后复检失败。' 
}
# 只接受本交付核验过的SDK版本，不更新全局安装。
accept_go() {
  [ -n "$1" ] && [ -x "$1" ] || return 1
  [ "$("$1" version 2>/dev/null | awk '{print $3}')" = "$GO_VERSION" ] || return 1
  GO_EXE="$1"
}
# 根据架构选择官方归档及固定摘要。
select_archive() {
  case "$(uname -m)" in
    arm64|aarch64) GO_ARCH=arm64 ;;
    x86_64|amd64) GO_ARCH=amd64 ;;
    *) fail '当前脚本仅提供amd64和arm64运行环境。' ;;
  esac
  case "$TARGET_OS-$GO_ARCH" in
    linux-amd64) GO_ARCHIVE=go1.27.3.linux-amd64.tar.gz; GO_SHA=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40 ;;
    linux-arm64) GO_ARCHIVE=go1.27.3.linux-arm64.tar.gz; GO_SHA=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49 ;;
    *) fail '没有当前平台官方SDK归档。' ;;
  esac
}
# 对下载归档校验，校验失败不解压。
verify_archive() {
  if command -v sha256sum >/dev/null 2>&1; then
    actual_hash="$(sha256sum "$1" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual_hash="$(shasum -a 256 "$1" | awk '{print $1}')"
  else
    actual_hash="$(sha256 -q "$1")"
  fi
  [ "$actual_hash" = "$GO_SHA" ] || fail 'SDK摘要不匹配，未解压。请检查网络与来源。'
}
# 缺SDK时下载到工程本地；已有健康SDK直接复用。
ensure_go() {
  if accept_go "${GO_BIN:-}"; then return; fi
  candidate_go="$(command -v go 2>/dev/null || true)"
  if accept_go "$candidate_go"; then return; fi
  if accept_go "$SERVER_ROOT/.tools/$GO_VERSION/bin/go"; then return; fi
  select_archive
  confirm_install "需要 $GO_VERSION：来源 https://go.dev/dl/$GO_ARCHIVE；目标 $SERVER_ROOT/.tools/$GO_VERSION"
  ensure_transfer_tools
  archive_path="$SERVER_ROOT/.tools/$GO_ARCHIVE"
  log "来源｜Go SDK｜https://go.dev/dl/$GO_ARCHIVE → $archive_path"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 --connect-timeout 15 --max-time 1200 "https://go.dev/dl/$GO_ARCHIVE" -o "$archive_path" >> "$LOG_FILE" 2>&1 || fail 'Go下载失败。'
  verify_archive "$archive_path"
  staging_dir="$(mktemp -d "$SERVER_ROOT/.tools/sdk-stage.XXXXXX")" || fail '无法建立临时目录。'
  tar -xzf "$archive_path" -C "$staging_dir" >> "$LOG_FILE" 2>&1 || fail 'SDK解压失败。'
  if [ -e "$SERVER_ROOT/.tools/$GO_VERSION" ]; then fail '本地SDK目录存在但不健康，保留原目录；移走后重试。'; fi
  mv "$staging_dir/go" "$SERVER_ROOT/.tools/$GO_VERSION"
  rmdir "$staging_dir"
  accept_go "$SERVER_ROOT/.tools/$GO_VERSION/bin/go" || fail 'Go安装后健康检查失败。'
}
# 隐藏输入密码，并限制换行以保证配置文件格式。
read_password() {
  printf '%s' "$1"
  stty -echo
  IFS= read -r CONFIG_PASSWORD || { stty echo; exit 1; }
  stty echo
  printf '\n'
  [ "${#CONFIG_PASSWORD}" -ge 12 ] || fail '密码至少12个字符。'
}
# 初次配置写一次，其后只读复用，禁止执行配置文本。
configure_server() {
  config_file="$SERVER_ROOT/.runtime/config.env"
  [ ! -L "$config_file" ] || fail "拒绝读取或写入符号链接配置。"
  if [ ! -f "$config_file" ]; then
    printf '%s' '监听地址 [127.0.0.1:8080]：'
    IFS= read -r config_listen || exit 1
    config_listen="${config_listen:-127.0.0.1:8080}"
    read_password '设置管理员admin密码（至少12字符）：'
    config_admin="$CONFIG_PASSWORD"
    read_password '设置客户customer密码（至少12字符，不能与管理员相同）：'
    [ "$CONFIG_PASSWORD" != "$config_admin" ] || fail '两个账户必须使用不同密码。'
    printf '%s' 'PostgreSQL连接串（直接回车使用单实例本地文件存储；输入隐藏）：'
    stty -echo
    IFS= read -r config_database || { stty echo; exit 1; }
    stty echo
    printf '\n'
    {
      printf 'APP_ENV=production\nLISTEN_ADDR=%s\nADMIN_PASSWORD=%s\nDEMO_CUSTOMER_PASSWORD=%s\nDATABASE_URL=%s\nCORS_ORIGINS=\n' "$config_listen" "$config_admin" "$CONFIG_PASSWORD" "$config_database"
    } > "$config_file"
    chmod 600 "$config_file"
    unset config_admin CONFIG_PASSWORD config_database
  fi
  [ ! -L "$config_file" ] || fail '拒绝读取符号链接配置。'
  while IFS= read -r config_line || [ -n "$config_line" ]; do
    case "$config_line" in ''|'#'*) continue ;; esac
    config_key="${config_line%%=*}"
    config_value="${config_line#*=}"
    case "$config_key" in
      APP_ENV|LISTEN_ADDR|ADMIN_PASSWORD|DEMO_CUSTOMER_PASSWORD|DATABASE_URL|CORS_ORIGINS|GOPROXY) export "$config_key=$config_value" ;;
      *) fail "未知配置键：$config_key" ;;
    esac
  done < "$config_file"
  export DATA_DIR="$SERVER_ROOT/data"
  export ADMIN_STATIC_DIR="$SERVER_ROOT/admin-web"
  export CLIENT_STATIC_DIR="$SERVER_ROOT/client-web"
  export GOPROXY="${GOPROXY:-https://goproxy.cn|https://proxy.golang.org|direct}"
  export GOTELEMETRY=off
  export GOMODCACHE="$SERVER_ROOT/.tools/gomodcache"
  export GOCACHE="$SERVER_ROOT/.tools/gobuildcache"
  export GOTOOLCHAIN=local
  export CGO_ENABLED=0
}
# 构建到临时文件，成功后替换程序，保留数据。
build_server() {
  check_source
  cd "$SERVER_ROOT"
  module_source="$(printf '%s' "$GOPROXY" | sed -E 's#(https?://)[^/@]*@#\1***@#g; s#\?[^|, ]*#?...#g')"
  log "来源｜Go依赖｜$module_source｜版本按go.mod/go.sum锁定｜缓存 $GOMODCACHE"
  log "构建｜$($GO_EXE version)｜$SERVER_ROOT"
  "$GO_EXE" build -trimpath -o "$SERVER_ROOT/.runtime/bin/server.next" ./cmd/server >> "$LOG_FILE" 2>&1 || fail '编译失败，原程序与数据已保留。'
  mv "$SERVER_ROOT/.runtime/bin/server.next" "$SERVER_ROOT/.runtime/bin/server"
  log '编译通过。'
}
# 前台运行便于新手看到错误，Ctrl+C可正常退出。
run_server() {
  log "启动｜监听 $LISTEN_ADDR｜管理端 /admin/｜Ctrl+C停止；运行日志 $LOG_FILE"
  if [ ! -f "$ADMIN_STATIC_DIR/index.html" ]; then log '管理端静态文件缺失；API仍可运行，请按说明先构建Flutter管理端。'; fi
  "$SERVER_ROOT/.runtime/bin/server" 2>&1 | tee -a "$LOG_FILE"
}
# 编排自述、环境准备与本目录部署。
main() {
  show_script_intro_and_wait "$@" # 先说明影响范围并等待确认。
  initialize_runtime # 确认后创建工程内日志和运行目录。
  check_platform # 拒绝不匹配的系统入口。
  check_source # 检查移植目录完整性。
  ensure_go # 复用SDK或安装工程本地SDK。
  configure_server # 初次配置账户，其后保留已有配置。
  build_server # 编译单份Go源码。
  run_server # 前台启动并保留日志。
}
main "$@"
