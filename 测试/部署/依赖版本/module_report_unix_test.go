//go:build !windows

package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestModuleReportTERMAlsoReapsItsOwnTree(t *testing.T) {
	sdk, module, modfile := reportFixture(t)
	heartbeat := filepath.Join(t.TempDir(), "heartbeat")
	raw, _ := json.Marshal(reportArgs(sdk, module, modfile, 20))
	cmd := exec.Command(sdk, "report-controller")
	cmd.Env = append(os.Environ(), "JOBS_REPORT_TEST_MODE=controller", "JOBS_REPORT_CONTROLLER_ARGS="+string(raw), "JOBS_REPORT_HEARTBEAT="+heartbeat)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	deadline := time.Now().Add(3 * time.Second)
	for {
		if _, err := os.Stat(heartbeat); err == nil {
			break
		}
		if time.Now().After(deadline) {
			_ = cmd.Process.Kill()
			t.Fatal("controller did not start child")
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 3 {
			t.Fatalf("TERM did not finish report cleanup: %v", err)
		}
	case <-time.After(5 * time.Second):
		_ = cmd.Process.Kill()
		t.Fatal("TERM cleanup hung")
	}
	if stdout.Len() != 0 {
		t.Fatal("canceled report output partial success")
	}
	first, _ := os.ReadFile(heartbeat)
	time.Sleep(150 * time.Millisecond)
	second, _ := os.ReadFile(heartbeat)
	if string(first) != string(second) {
		t.Fatal("TERM left Go descendant alive")
	}
}
