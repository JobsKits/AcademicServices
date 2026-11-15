package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"
)

const reportOutputLimit = 4 * 1024 * 1024

var reportField = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._~+/-]*$`)

type sourceSnapshot struct {
	path   string
	info   os.FileInfo
	hash   [32]byte
	exists bool
}

func snapshotFile(path string, required bool) (sourceSnapshot, error) {
	result := sourceSnapshot{path: path}
	info, err := os.Lstat(path)
	if os.IsNotExist(err) && !required {
		return result, nil
	}
	if err != nil || !info.Mode().IsRegular() {
		return result, errors.New("模块清单必须是可读普通文件，不能是符号链接")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return result, errors.New("无法读取模块清单")
	}
	result.info, result.hash, result.exists = info, sha256.Sum256(raw), true
	return result, nil
}
func unchanged(before sourceSnapshot) bool {
	after, err := snapshotFile(before.path, before.exists)
	return err == nil && before.exists == after.exists && before.hash == after.hash && (!before.exists || os.SameFile(before.info, after.info))
}
func withinDirectory(root, path string) bool {
	relative, err := filepath.Rel(root, path)
	return err == nil && (relative == "." || relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative))
}
func validateReportPaths(goBin, moduleDir, modfile string) (string, string, string, []sourceSnapshot, error) {
	if !filepath.IsAbs(goBin) {
		return "", "", "", nil, errors.New("go-bin须为已验证SDK的绝对可执行路径")
	}
	sdk, err := filepath.EvalSymlinks(goBin)
	if err != nil {
		return "", "", "", nil, errors.New("Go SDK路径不可用")
	}
	info, err := os.Stat(sdk)
	if err != nil || !info.Mode().IsRegular() {
		return "", "", "", nil, errors.New("Go SDK必须为普通可执行文件")
	}
	module, err := filepath.Abs(moduleDir)
	if err != nil {
		return "", "", "", nil, errors.New("模块路径无效")
	}
	module, err = filepath.EvalSymlinks(module)
	if err != nil {
		return "", "", "", nil, errors.New("模块目录不存在")
	}
	info, err = os.Stat(module)
	if err != nil || !info.IsDir() {
		return "", "", "", nil, errors.New("模块目录不存在")
	}
	sourceMod, err := snapshotFile(filepath.Join(module, "go.mod"), true)
	if err != nil {
		return "", "", "", nil, err
	}
	sourceSum, err := snapshotFile(filepath.Join(module, "go.sum"), false)
	if err != nil {
		return "", "", "", nil, err
	}
	temporary, err := filepath.Abs(modfile)
	if err != nil || filepath.Ext(temporary) != ".mod" || filepath.Base(temporary) == "go.mod" {
		return "", "", "", nil, errors.New("modfile须为模块外运行目录中的临时.mod副本")
	}
	tempMod, err := snapshotFile(temporary, true)
	if err != nil {
		return "", "", "", nil, err
	}
	canonical, err := filepath.EvalSymlinks(temporary)
	if err != nil || withinDirectory(module, canonical) {
		return "", "", "", nil, errors.New("临时modfile不能位于源码模块内")
	}
	sumPath := strings.TrimSuffix(temporary, ".mod") + ".sum"
	tempSum, err := snapshotFile(sumPath, sourceSum.exists)
	if err != nil {
		return "", "", "", nil, err
	}
	if tempSum.exists {
		sumCanonical, err := filepath.EvalSymlinks(sumPath)
		if err != nil || withinDirectory(module, sumCanonical) {
			return "", "", "", nil, errors.New("临时sum不能指向源码模块")
		}
	}
	if tempMod.hash != sourceMod.hash || sourceSum.exists != tempSum.exists || sourceSum.hash != tempSum.hash {
		return "", "", "", nil, errors.New("临时modfile及sum须为当前源码清单的完整副本")
	}
	for _, temp := range []sourceSnapshot{tempMod, tempSum} {
		for _, source := range []sourceSnapshot{sourceMod, sourceSum} {
			if temp.exists && source.exists && os.SameFile(temp.info, source.info) {
				return "", "", "", nil, errors.New("临时模块副本不能与源码清单共用文件或硬链接")
			}
		}
	}
	return sdk, module, temporary, []sourceSnapshot{sourceMod, sourceSum}, nil
}

type limitedReportBuffer struct {
	bytes.Buffer
	overflow bool
}

func (b *limitedReportBuffer) Write(value []byte) (int, error) {
	if b.Len()+len(value) > reportOutputLimit {
		b.overflow = true
		return 0, errors.New("module report output limit")
	}
	return b.Buffer.Write(value)
}
func reportEnvironment() []string {
	result := []string{}
	for _, entry := range os.Environ() {
		key, _, _ := strings.Cut(entry, "=")
		if !strings.EqualFold(key, "GOWORK") && !strings.EqualFold(key, "GOTOOLCHAIN") {
			result = append(result, entry)
		}
	}
	return append(result, "GOWORK=off", "GOTOOLCHAIN=local")
}
func executeModuleReport(ctx context.Context, sdk, module, modfile string) ([]byte, error) {
	cmd := exec.Command(sdk, "list", "-m", "-u", "-json", "-mod=readonly", "-modfile="+modfile, "all")
	cmd.Dir = module
	cmd.Env = reportEnvironment()
	cmd.WaitDelay = time.Second
	var output, stderr limitedReportBuffer
	cmd.Stdout = &output
	cmd.Stderr = &stderr
	scope, err := newProcessScope(cmd)
	if err != nil {
		return nil, err
	}
	defer scope.close()
	if err = cmd.Start(); err != nil {
		return nil, errors.New("依赖检查未完成：无法启动已验证Go SDK")
	}
	if err = scope.attach(cmd); err != nil {
		_ = scope.kill(cmd)
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		return nil, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err = <-done:
		if cleanupErr := scope.kill(cmd); cleanupErr != nil {
			return nil, cleanupErr
		}
		if err != nil || output.overflow || stderr.overflow {
			return nil, errors.New("依赖检查未完成：Go查询失败或输出超限；未修改已确认版本")
		}
	case <-ctx.Done():
		if err = scope.kill(cmd); err != nil {
			_ = cmd.Process.Kill()
			return nil, err
		}
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			return nil, errors.New("依赖检查超时；子进程回收仍未完成")
		}
		if errors.Is(ctx.Err(), context.Canceled) {
			return nil, errors.New("依赖检查已中止：已停止本次Go及其子进程")
		}
		return nil, errors.New("依赖检查未完成：达到本次时限，已停止本次Go及其子进程")
	}
	return output.Bytes(), nil
}
func formatModuleReport(raw []byte) (string, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	rows := map[string]string{}
	count := 0
	for {
		var item struct {
			Path, Version string
			Main          bool
			Update        *struct{ Path, Version string }
			Error         *struct{ Err string }
		}
		err := decoder.Decode(&item)
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", errors.New("依赖检查未完成：Go报告不是有效JSON")
		}
		count++
		if item.Error != nil {
			return "", errors.New("依赖检查未完成：部分模块查询失败")
		}
		if item.Main || item.Update == nil {
			continue
		}
		if !reportField.MatchString(item.Path) || !reportField.MatchString(item.Version) || !reportField.MatchString(item.Update.Version) || item.Update.Path != "" && item.Update.Path != item.Path {
			return "", errors.New("依赖检查未完成：模块报告字段无效")
		}
		if _, exists := rows[item.Path]; exists {
			return "", errors.New("依赖检查未完成：模块报告含重复记录")
		}
		rows[item.Path] = item.Path + "\t" + item.Version + "\t" + item.Update.Version + "\n"
	}
	if count == 0 {
		return "", errors.New("依赖检查未完成：Go未返回模块报告")
	}
	paths := make([]string, 0, len(rows))
	for path := range rows {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	var result strings.Builder
	for _, path := range paths {
		result.WriteString(rows[path])
	}
	return result.String(), nil
}
func runModuleReport(goBin, moduleDir, modfile string, seconds int, out, stderr io.Writer) int {
	fail := func(message string, code int) int { fmt.Fprintln(stderr, message); return code }
	if seconds < 1 || seconds > 300 {
		return fail("报告时限须为1—300秒", 2)
	}
	sdk, module, temporary, snapshots, err := validateReportPaths(goBin, moduleDir, modfile)
	if err != nil {
		return fail(err.Error(), 2)
	}
	signalContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(signalContext, time.Duration(seconds)*time.Second)
	defer cancel()
	raw, queryErr := executeModuleReport(ctx, sdk, module, temporary)
	for _, before := range snapshots {
		if !unchanged(before) {
			return fail("依赖检查未完成：源码mod/sum已变化，请核对；未自动恢复或提交", 2)
		}
	}
	if queryErr != nil {
		return fail(queryErr.Error(), 3)
	}
	report, err := formatModuleReport(raw)
	if err != nil {
		return fail(err.Error(), 3)
	}
	fmt.Fprint(out, report)
	return 0
}
