// Jobs · 只读解析官方稳定版本与资产摘要；安装和生命周期留在各平台入口。
package main

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/csv"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const (
	goMetadataURL = "https://go.dev/dl/?mode=json"
	metadataLimit = 8 * 1024 * 1024
	queryTimeout  = 15 * time.Second
)

var (
	versionPattern    = regexp.MustCompile(`^(?:go|v)?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?$`)
	shaPattern        = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)
	manifestHeader    = []string{"tool", "os", "arch", "version", "filename", "sha256", "url", "kind"}
	errSourceRedirect = errors.New("官方元数据接口重定向，拒绝切换来源")
)

type retryableMetadataError struct{ err error }

func (e retryableMetadataError) Error() string { return e.err.Error() }
func (e retryableMetadataError) Unwrap() error { return e.err }

type releaseRecord struct {
	Tool, OS, Arch, Version, Filename, SHA256, URL, Kind string
}

func (r releaseRecord) fields() []string {
	return []string{r.Tool, r.OS, r.Arch, r.Version, r.Filename, r.SHA256, r.URL, r.Kind}
}

func unsupported(tool, platform, arch, version string) releaseRecord {
	return releaseRecord{tool, platform, arch, version, "-", "-", "-", "unsupported"}
}

func parseVersion(value string) ([3]uint64, error) {
	var result [3]uint64
	match := versionPattern.FindStringSubmatch(value)
	if match == nil {
		return result, errors.New("版本须为正式数字版本，例如 1.27.4、v0.75.0；不接受预发布或附加文字")
	}
	for i := range result {
		if match[i+1] == "" {
			continue
		}
		n, err := strconv.ParseUint(match[i+1], 10, 32)
		if err != nil {
			return result, errors.New("版本数字超出范围")
		}
		result[i] = n
	}
	return result, nil
}

func compareVersion(left, right string) (int, error) {
	a, err := parseVersion(left)
	if err != nil {
		return 0, err
	}
	b, err := parseVersion(right)
	if err != nil {
		return 0, err
	}
	for i := range a {
		if a[i] < b[i] {
			return -1, nil
		}
		if a[i] > b[i] {
			return 1, nil
		}
	}
	return 0, nil
}

func officialClient() *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.DialContext = (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext
	transport.TLSHandshakeTimeout = 5 * time.Second
	transport.ResponseHeaderTimeout = 8 * time.Second
	return &http.Client{
		Timeout:   queryTimeout,
		Transport: transport,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return errSourceRedirect
		},
	}
}

type versionResolver struct{ client *http.Client }

func (v versionResolver) readJSON(ctx context.Context, endpoint string, target any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	request.Header.Set("User-Agent", "JobsDeployVersionResolver/1")
	request.Header.Set("Accept", "application/json")
	if strings.HasPrefix(endpoint, "https://api.github.com/") {
		request.Header.Set("Accept", "application/vnd.github+json")
		request.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	}
	response, err := v.client.Do(request)
	if err != nil {
		var unknown x509.UnknownAuthorityError
		var invalid x509.CertificateInvalidError
		var hostname x509.HostnameError
		if errors.Is(err, errSourceRedirect) || errors.As(err, &unknown) || errors.As(err, &invalid) || errors.As(err, &hostname) {
			return fmt.Errorf("官方元数据来源或证书校验失败: %w", err)
		}
		return retryableMetadataError{fmt.Errorf("查询官方版本元数据暂时失败: %w", err)}
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		err := fmt.Errorf("官方版本元数据返回 HTTP %d", response.StatusCode)
		if response.StatusCode == 429 || response.StatusCode >= 500 && response.StatusCode <= 599 || response.StatusCode == 403 && strings.HasPrefix(endpoint, "https://api.github.com/") && response.Header.Get("X-RateLimit-Remaining") == "0" {
			return retryableMetadataError{err}
		}
		return err
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, metadataLimit+1))
	if err != nil {
		return retryableMetadataError{fmt.Errorf("读取官方元数据暂时失败: %w", err)}
	}
	if len(raw) > metadataLimit {
		return errors.New("官方版本元数据超出大小限制")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	if err := decoder.Decode(target); err != nil {
		return errors.New("官方版本元数据不是有效 JSON")
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return errors.New("官方版本元数据含额外内容")
	}
	return nil
}

type goRelease struct {
	Version string `json:"version"`
	Stable  bool   `json:"stable"`
	Files   []struct {
		Filename string `json:"filename"`
		OS       string `json:"os"`
		Arch     string `json:"arch"`
		Version  string `json:"version"`
		SHA256   string `json:"sha256"`
		Kind     string `json:"kind"`
	} `json:"files"`
}

func (v versionResolver) resolveGo(ctx context.Context, platform, arch, minimum string) (releaseRecord, error) {
	var releases []goRelease
	if err := v.readJSON(ctx, goMetadataURL, &releases); err != nil {
		return releaseRecord{}, err
	}
	var latest *goRelease
	for i := range releases {
		candidate := &releases[i]
		if !candidate.Stable {
			continue
		}
		if !strings.HasPrefix(candidate.Version, "go") {
			return releaseRecord{}, errors.New("Go 正式版本缺少 go 前缀")
		}
		if _, err := parseVersion(candidate.Version); err != nil {
			return releaseRecord{}, fmt.Errorf("Go 正式版本标记无效: %w", err)
		}
		if latest == nil {
			latest = candidate
			continue
		}
		order, _ := compareVersion(candidate.Version, latest.Version)
		if order > 0 {
			latest = candidate
		} else if order == 0 {
			return releaseRecord{}, errors.New("Go 官方元数据含重复正式版本")
		}
	}
	if latest == nil {
		return releaseRecord{}, errors.New("Go 官方元数据没有正式稳定版")
	}
	version := strings.TrimPrefix(latest.Version, "go")
	if minimum != "" {
		order, err := compareVersion(version, minimum)
		if err != nil {
			return releaseRecord{}, err
		}
		if order < 0 {
			return releaseRecord{}, fmt.Errorf("最新 Go %s 低于项目要求 %s", version, minimum)
		}
	}
	result := unsupported("go", platform, arch, version)
	extension, kind := ".tar.gz", "tar.gz"
	if platform == "windows" {
		extension, kind = ".zip", "zip"
	}
	expected := "go" + version + "." + platform + "-" + arch + extension
	found := false
	for _, file := range latest.Files {
		if file.OS != platform || file.Arch != arch || file.Kind != "archive" {
			continue
		}
		if found || file.Filename != expected || file.Version != latest.Version || !shaPattern.MatchString(file.SHA256) {
			return releaseRecord{}, errors.New("Go 目标归档名称、版本或 SHA256 不符合官方合同")
		}
		found = true
		result = releaseRecord{"go", platform, arch, version, expected, strings.ToLower(file.SHA256), "https://go.dev/dl/" + expected, kind}
	}
	return result, nil
}

type githubRelease struct {
	Tag        string `json:"tag_name"`
	Draft      bool   `json:"draft"`
	Prerelease bool   `json:"prerelease"`
	Assets     []struct {
		Name   string `json:"name"`
		URL    string `json:"browser_download_url"`
		Digest string `json:"digest"`
	} `json:"assets"`
}

func githubTarget(tool, platform, arch, version string) (repo, tag, name, kind string) {
	if tool == "fzf" {
		extension := ".tar.gz"
		kind = "tar.gz"
		if platform == "windows" {
			extension, kind = ".zip", "zip"
		}
		return "junegunn/fzf", "v" + version, "fzf-" + version + "-" + platform + "_" + arch + extension, kind
	}
	name, kind = "cloudflared-"+platform+"-"+arch, "binary"
	if platform == "darwin" {
		name, kind = name+".tgz", "tar.gz"
	} else if platform == "windows" {
		name += ".exe"
	}
	return "cloudflare/cloudflared", version, name, kind
}

func (v versionResolver) resolveGitHub(ctx context.Context, tool, platform, arch, lockPath string) (releaseRecord, error) {
	repo, _, _, _ := githubTarget(tool, platform, arch, "0.0.0")
	var release githubRelease
	if err := v.readJSON(ctx, "https://api.github.com/repos/"+repo+"/releases/latest", &release); err != nil {
		return releaseRecord{}, err
	}
	if release.Draft || release.Prerelease {
		return releaseRecord{}, errors.New("GitHub latest 不是正式稳定发布")
	}
	version := release.Tag
	if tool == "fzf" {
		if !strings.HasPrefix(version, "v") {
			return releaseRecord{}, errors.New("fzf 正式版本标记须以 v 开头")
		}
		version = strings.TrimPrefix(version, "v")
	}
	if _, err := parseVersion(version); err != nil || strings.HasPrefix(version, "go") || strings.HasPrefix(version, "v") || strings.Count(version, ".") != 2 {
		return releaseRecord{}, errors.New("GitHub 正式版本标记不是三段数字版本")
	}
	_, tag, name, kind := githubTarget(tool, platform, arch, version)
	expectedURL := "https://github.com/" + repo + "/releases/download/" + tag + "/" + name
	result := unsupported(tool, platform, arch, version)
	found := false
	for _, asset := range release.Assets {
		if asset.Name != name {
			continue
		}
		if found || asset.URL != expectedURL {
			return releaseRecord{}, errors.New("GitHub 目标资产重复或下载地址不符合官方合同")
		}
		found = true
		result = releaseRecord{tool, platform, arch, version, name, "", expectedURL, kind}
		if asset.Digest == "" {
			digest, err := lockedDigest(lockPath, result)
			if err != nil {
				return releaseRecord{}, err
			}
			result.SHA256 = digest
		} else {
			if !strings.HasPrefix(asset.Digest, "sha256:") || !shaPattern.MatchString(strings.TrimPrefix(asset.Digest, "sha256:")) {
				return releaseRecord{}, errors.New("GitHub 目标资产没有有效 SHA256 digest")
			}
			result.SHA256 = strings.ToLower(strings.TrimPrefix(asset.Digest, "sha256:"))
		}
	}
	return result, nil
}

// 旧锁只能补同一最新发布、平台及资产的缺失摘要，不能回退版本。
func lockedDigest(path string, expected releaseRecord) (string, error) {
	if path == "" {
		return "", errors.New("最新官方资产缺少 digest，且未提供可精确匹配的受控锁清单")
	}
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("读取受控锁清单失败: %w", err)
	}
	defer file.Close()
	raw, err := io.ReadAll(io.LimitReader(file, 1024*1024+1))
	if err != nil || len(raw) > 1024*1024 {
		return "", errors.New("受控锁清单不可读或超出大小限制")
	}
	reader := csv.NewReader(bytes.NewReader(raw))
	reader.Comma = '\t'
	reader.FieldsPerRecord = 8
	header, err := reader.Read()
	if err != nil || strings.Join(header, "\t") != strings.Join(manifestHeader, "\t") {
		return "", errors.New("受控锁清单表头无效")
	}
	digest := ""
	for {
		fields, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", errors.New("受控锁清单 TSV 格式无效")
		}
		if fields[0] != expected.Tool || fields[1] != expected.OS || fields[2] != expected.Arch || fields[3] != expected.Version || fields[4] != expected.Filename || fields[6] != expected.URL || fields[7] != expected.Kind {
			continue
		}
		if digest != "" || !shaPattern.MatchString(fields[5]) {
			return "", errors.New("受控锁清单摘要无效或目标条目重复")
		}
		digest = strings.ToLower(fields[5])
	}
	if digest == "" {
		return "", errors.New("最新官方资产缺少 digest，受控锁清单没有同版本、平台、文件及URL的摘要")
	}
	return digest, nil
}

func run(args []string, out, errOut io.Writer, client *http.Client) int {
	flags := flag.NewFlagSet("deploy-versions", flag.ContinueOnError)
	flags.SetOutput(errOut)
	tool := flags.String("tool", "", "go、fzf 或 cloudflared")
	platform := flags.String("os", "", "darwin、linux、windows 或 freebsd")
	arch := flags.String("arch", "", "amd64 或 arm64")
	minimum := flags.String("minimum-go", "", "项目最低 Go 正式版本")
	lockPath := flags.String("locked-manifest", "", "仅补同版本资产缺失摘要的受控 TSV")
	installed := flags.String("compare", "", "比较已安装正式版本")
	latest := flags.String("at-least", "", "比较要求的正式版本")
	moduleReport := flags.Bool("module-report", false, "只读检查临时模块副本的可用更新")
	goBin := flags.String("go-bin", "", "调用方已验证的Go SDK绝对路径")
	moduleDir := flags.String("module-dir", "", "源码Go模块目录")
	modfile := flags.String("modfile", "", "模块外运行目录中的临时.mod副本")
	reportSeconds := flags.Int("timeout-seconds", 30, "只读模块检查时限，1—300秒")
	failure := func(err error) int {
		fmt.Fprintln(errOut, err)
		var retry retryableMetadataError
		if errors.As(err, &retry) {
			return 75
		}
		return 2
	}
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 0 {
		return failure(errors.New("不接受位置参数"))
	}
	if *moduleReport {
		if *goBin == "" || *moduleDir == "" || *modfile == "" || *tool != "" || *platform != "" || *arch != "" || *minimum != "" || *lockPath != "" || *installed != "" || *latest != "" {
			return failure(errors.New("module-report仅接受go-bin、module-dir、modfile及timeout-seconds"))
		}
		return runModuleReport(*goBin, *moduleDir, *modfile, *reportSeconds, out, errOut)
	}
	reportFlags := false
	flags.Visit(func(f *flag.Flag) {
		if f.Name == "go-bin" || f.Name == "module-dir" || f.Name == "modfile" || f.Name == "timeout-seconds" {
			reportFlags = true
		}
	})
	if reportFlags {
		return failure(errors.New("报告参数须与module-report模式一起使用"))
	}
	if *installed != "" || *latest != "" {
		if *installed == "" || *latest == "" || *tool != "" || *platform != "" || *arch != "" || *minimum != "" || *lockPath != "" {
			return failure(errors.New("比较模式仅接受 --compare 与 --at-least"))
		}
		order, err := compareVersion(*installed, *latest)
		if err != nil {
			return failure(err)
		}
		if order >= 0 {
			fmt.Fprintln(out, "1")
		} else {
			fmt.Fprintln(out, "0")
			return 1
		}
		return 0
	}
	if *tool != "go" && *tool != "fzf" && *tool != "cloudflared" {
		return failure(errors.New("请选择受支持的 tool"))
	}
	if *platform != "darwin" && *platform != "linux" && *platform != "windows" && *platform != "freebsd" {
		return failure(errors.New("请选择受支持的 os"))
	}
	if *arch != "amd64" && *arch != "arm64" {
		return failure(errors.New("请选择受支持的 arch"))
	}
	if *minimum != "" {
		if *tool != "go" {
			return failure(errors.New("minimum-go 仅适用于 Go 查询"))
		}
		if _, err := parseVersion(*minimum); err != nil {
			return failure(err)
		}
	}
	if client == nil {
		client = officialClient()
	}
	ctx, cancel := context.WithTimeout(context.Background(), queryTimeout)
	defer cancel()
	resolver := versionResolver{client: client}
	var record releaseRecord
	var err error
	if *tool == "go" {
		record, err = resolver.resolveGo(ctx, *platform, *arch, *minimum)
	} else {
		record, err = resolver.resolveGitHub(ctx, *tool, *platform, *arch, *lockPath)
	}
	if err != nil {
		return failure(err)
	}
	fmt.Fprintln(out, strings.Join(record.fields(), "\t"))
	return 0
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, nil)) }
