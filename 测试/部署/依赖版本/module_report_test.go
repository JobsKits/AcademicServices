package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestMain(m *testing.M) {
	mode := os.Getenv("JOBS_REPORT_TEST_MODE")
	if mode == "" {
		os.Exit(m.Run())
	}
	if mode == "controller" {
		var args []string
		if json.Unmarshal([]byte(os.Getenv("JOBS_REPORT_CONTROLLER_ARGS")), &args) != nil {
			os.Exit(54)
		}
		_ = os.Setenv("JOBS_REPORT_TEST_MODE", "spawn")
		os.Exit(run(args, os.Stdout, os.Stderr, nil))
	}
	if mode == "heartbeat" {
		for {
			_ = os.WriteFile(os.Getenv("JOBS_REPORT_HEARTBEAT"), []byte(strconv.FormatInt(time.Now().UnixNano(), 10)), 0600)
			time.Sleep(20 * time.Millisecond)
		}
	}
	if os.Getenv("GOWORK") != "off" || os.Getenv("GOTOOLCHAIN") != "local" {
		os.Exit(51)
	}
	if target := os.Getenv("JOBS_REPORT_ARGS"); target != "" {
		raw, _ := json.Marshal(os.Args[1:])
		_ = os.WriteFile(target, raw, 0600)
	}
	switch mode {
	case "success":
		fmt.Println(`{"Path":"sample.local/app","Main":true}`)
		fmt.Println(`{"Path":"example.com/z","Version":"v1.0.0","Update":{"Path":"example.com/z","Version":"v1.1.0"}}`)
		fmt.Println(`{"Path":"example.com/a","Version":"v0.0.0-20240101000000-abcdef123456","Update":{"Version":"v1.0.0"}}`)
	case "no-update":
		fmt.Println(`{"Path":"sample.local/app","Main":true}`)
	case "error":
		fmt.Fprintln(os.Stderr, "secret-token=must-never-be-forwarded")
		os.Exit(7)
	case "invalid-json":
		fmt.Println("not-json")
	case "mutate":
		_ = os.WriteFile(os.Getenv("JOBS_REPORT_SOURCE"), []byte("changed independently"), 0600)
		fmt.Println(`{"Path":"sample.local/app","Main":true}`)
	case "spawn":
		child := exec.Command(os.Args[0], "heartbeat-child")
		child.Env = append(os.Environ(), "JOBS_REPORT_TEST_MODE=heartbeat")
		if err := child.Start(); err != nil {
			os.Exit(52)
		}
		time.Sleep(10 * time.Second)
	default:
		os.Exit(53)
	}
	os.Exit(0)
}
func reportFixture(t *testing.T) (string, string, string) {
	t.Helper()
	module := filepath.Join(t.TempDir(), "Module")
	temporary := filepath.Join(t.TempDir(), "Report")
	if err := os.MkdirAll(module, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(temporary, 0700); err != nil {
		t.Fatal(err)
	}
	mod := []byte("module sample.local/app\n\ngo 1.24.0\n")
	sum := []byte("synthetic-original-checksum\n")
	for path, raw := range map[string][]byte{filepath.Join(module, "go.mod"): mod, filepath.Join(module, "go.sum"): sum, filepath.Join(temporary, "check.mod"): mod, filepath.Join(temporary, "check.sum"): sum} {
		if err := os.WriteFile(path, raw, 0600); err != nil {
			t.Fatal(err)
		}
	}
	sdk, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	return sdk, module, filepath.Join(temporary, "check.mod")
}
func reportArgs(sdk, module, modfile string, seconds int) []string {
	return []string{"--module-report", "--go-bin", sdk, "--module-dir", module, "--modfile", modfile, "--timeout-seconds", strconv.Itoa(seconds)}
}
func TestModuleReportUsesOnlyFixedCommandAndTemporaryFiles(t *testing.T) {
	sdk, module, modfile := reportFixture(t)
	argsFile := filepath.Join(t.TempDir(), "args.json")
	t.Setenv("JOBS_REPORT_TEST_MODE", "success")
	t.Setenv("JOBS_REPORT_ARGS", argsFile)
	t.Setenv("GOWORK", "must-not-be-used")
	t.Setenv("GOTOOLCHAIN", "must-not-download")
	beforeMod, _ := os.ReadFile(filepath.Join(module, "go.mod"))
	beforeSum, _ := os.ReadFile(filepath.Join(module, "go.sum"))
	code, out, stderr := execute(t, nil, reportArgs(sdk, module, modfile, 5)...)
	if code != 0 || stderr != "" || out != "example.com/a\tv0.0.0-20240101000000-abcdef123456\tv1.0.0\nexample.com/z\tv1.0.0\tv1.1.0\n" {
		t.Fatalf("%d %q %q", code, out, stderr)
	}
	raw, _ := os.ReadFile(argsFile)
	var got []string
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []string{"list", "-m", "-u", "-json", "-mod=readonly", "-modfile=" + modfile, "all"}) {
		t.Fatalf("arbitrary or missing arguments: %q", got)
	}
	afterMod, _ := os.ReadFile(filepath.Join(module, "go.mod"))
	afterSum, _ := os.ReadFile(filepath.Join(module, "go.sum"))
	if string(beforeMod) != string(afterMod) || string(beforeSum) != string(afterSum) {
		t.Fatal("source changed")
	}
}
func TestModuleReportDoesNotLeakFailuresOrConfuseNoUpdates(t *testing.T) {
	for _, mode := range []string{"no-update", "error", "invalid-json", "mutate"} {
		t.Run(mode, func(t *testing.T) {
			sdk, module, modfile := reportFixture(t)
			t.Setenv("JOBS_REPORT_TEST_MODE", mode)
			t.Setenv("JOBS_REPORT_SOURCE", filepath.Join(module, "go.mod"))
			code, out, stderr := execute(t, nil, reportArgs(sdk, module, modfile, 5)...)
			want := 3
			if mode == "no-update" {
				want = 0
			}
			if mode == "mutate" {
				want = 2
			}
			if code != want || out != "" || strings.Contains(stderr, "secret-token") || strings.Contains(stderr, "must-never") {
				t.Fatalf("%s: %d %q %q", mode, code, out, stderr)
			}
			if mode != "no-update" && stderr == "" {
				t.Fatal("failed report has no reason")
			}
		})
	}
}
func TestModuleReportRejectsOriginalInModuleAndLinkedCopies(t *testing.T) {
	for _, issue := range []string{"original", "inside", "symlink", "hardlink", "wrong-copy", "missing-sum", "linked-sum", "timeout-zero", "timeout-long", "relative-go"} {
		t.Run(issue, func(t *testing.T) {
			sdk, module, modfile := reportFixture(t)
			seconds := 5
			switch issue {
			case "original":
				modfile = filepath.Join(module, "go.mod")
			case "inside":
				inside := filepath.Join(module, "check.mod")
				raw, _ := os.ReadFile(modfile)
				_ = os.WriteFile(inside, raw, 0600)
				modfile = inside
			case "symlink":
				_ = os.Remove(modfile)
				if err := os.Symlink(filepath.Join(module, "go.mod"), modfile); err != nil {
					t.Skipf("symlink unavailable: %v", err)
				}
			case "hardlink":
				_ = os.Remove(modfile)
				if err := os.Link(filepath.Join(module, "go.mod"), modfile); err != nil {
					t.Fatal(err)
				}
			case "wrong-copy":
				_ = os.WriteFile(modfile, []byte("module changed.local/app\n"), 0600)
			case "missing-sum":
				_ = os.Remove(strings.TrimSuffix(modfile, ".mod") + ".sum")
			case "linked-sum":
				p := strings.TrimSuffix(modfile, ".mod") + ".sum"
				_ = os.Remove(p)
				if err := os.Link(filepath.Join(module, "go.sum"), p); err != nil {
					t.Fatal(err)
				}
			case "timeout-zero":
				seconds = 0
			case "timeout-long":
				seconds = 301
			case "relative-go":
				sdk = "go"
			}
			code, out, stderr := execute(t, nil, reportArgs(sdk, module, modfile, seconds)...)
			if code != 2 || out != "" || stderr == "" {
				t.Fatalf("accepted %s: %d %q %q", issue, code, out, stderr)
			}
		})
	}
}
func TestModuleReportTimeoutReapsItsOwnChildTree(t *testing.T) {
	sdk, module, modfile := reportFixture(t)
	heartbeat := filepath.Join(t.TempDir(), "heartbeat")
	t.Setenv("JOBS_REPORT_TEST_MODE", "spawn")
	t.Setenv("JOBS_REPORT_HEARTBEAT", heartbeat)
	started := time.Now()
	code, out, stderr := execute(t, nil, reportArgs(sdk, module, modfile, 1)...)
	if code != 3 || out != "" || !strings.Contains(stderr, "时限") || time.Since(started) > 4*time.Second {
		t.Fatalf("%d %q %q", code, out, stderr)
	}
	first, err := os.ReadFile(heartbeat)
	if err != nil {
		t.Fatal("child did not run before cancellation", err)
	}
	time.Sleep(150 * time.Millisecond)
	second, err := os.ReadFile(heartbeat)
	if err != nil {
		t.Fatal(err)
	}
	if string(first) != string(second) {
		t.Fatal("child heartbeat continued after timeout")
	}
}
func TestModuleReportRejectsUnsafeReportFieldsAndPartialErrors(t *testing.T) {
	for _, raw := range []string{
		`{"Path":"example.com/a","Version":"v1","Update":{"Version":"v2"},"Error":{"Err":"private credential"}}`,
		`{"Path":"example.com/a\tsecret","Version":"v1","Update":{"Version":"v2"}}`,
		`{"Path":"example.com/a","Version":"v1","Update":{"Path":"other.local/a","Version":"v2"}}`,
		`{"Path":"example.com/a","Version":"v1","Update":{"Version":"v2"}} {"Path":"example.com/a","Version":"v1","Update":{"Version":"v2"}}`,
		"",
	} {
		out, err := formatModuleReport([]byte(raw))
		if err == nil || out != "" {
			t.Fatal("unsafe partial report", out, err)
		}
	}
	code, out, stderr := execute(t, nil, "--tool", "go", "--os", "linux", "--arch", "amd64", "--timeout-seconds", "30")
	if code != 2 || out != "" || stderr == "" {
		t.Fatal("report flags accepted in metadata mode")
	}
}
