// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// This child process gives the parent a real kernel lock and abrupt-exit boundary.
func TestFileStoreLockProcessHelper(t *testing.T) {
	mode := os.Getenv("ACADEMIC_STORE_LOCK_HELPER")
	if mode == "" || mode == "exit" {
		return
	}
	store, err := OpenFileStore(os.Getenv("ACADEMIC_STORE_LOCK_DIR"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	if mode == "try" {
		return
	}
	if err = store.Update(testCtx, func(state *State) error {
		state.Services[0].Name = "crash-preserved"
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	fmt.Println("store-ready")
	for {
		time.Sleep(time.Hour)
	}
}

func fileStoreLockHelperCommand(t *testing.T, dir, mode string) *exec.Cmd {
	t.Helper()
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(executable, "-test.run=^TestFileStoreLockProcessHelper$")
	cmd.Env = append(os.Environ(), "ACADEMIC_STORE_LOCK_HELPER="+mode, "ACADEMIC_STORE_LOCK_DIR="+dir)
	return cmd
}

func startFileStoreLockHelper(t *testing.T, dir string) (*exec.Cmd, func()) {
	t.Helper()
	cmd := fileStoreLockHelperCommand(t, dir, "hold")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err = cmd.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	var once sync.Once
	stop := func() {
		once.Do(func() {
			_ = cmd.Process.Kill()
			<-done
		})
	}
	t.Cleanup(stop)
	ready := make(chan string, 1)
	go func() {
		scanner := bufio.NewScanner(stdout)
		if scanner.Scan() {
			ready <- scanner.Text()
			return
		}
		ready <- ""
	}()
	select {
	case line := <-ready:
		if line != "store-ready" {
			stop()
			t.Fatalf("helper did not acquire store: %q, %s", line, stderr.String())
		}
	case <-time.After(60 * time.Second):
		stop()
		t.Fatal("helper lock acquisition timed out")
	}
	return cmd, stop
}

func TestFileStoreDarwinConcurrentProcessAndCrashRecovery(t *testing.T) {
	dir := t.TempDir()
	_, stop := startFileStoreLockHelper(t, dir)
	markerPath := filepath.Join(dir, ".server-lock")
	marker, err := os.ReadFile(markerPath)
	if err != nil {
		t.Fatal(err)
	}
	statePath := filepath.Join(dir, "state.json")
	state, err := os.ReadFile(statePath)
	if err != nil {
		t.Fatal(err)
	}
	if output, err := fileStoreLockHelperCommand(t, dir, "try").CombinedOutput(); err == nil {
		t.Fatalf("independent process acquired an occupied store: %s", output)
	}
	if after, _ := os.ReadFile(markerPath); !bytes.Equal(after, marker) {
		t.Fatal("competing process changed the active marker")
	}
	stop()
	store, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal("SIGKILL left the store blocked", err)
	}
	defer store.Close()
	if err = store.View(testCtx, func(state *State) error {
		if state.Services[0].Name != "crash-preserved" {
			t.Fatal("lost committed business data after crash")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if after, _ := os.ReadFile(statePath); !bytes.Equal(after, state) {
		t.Fatal("recovery changed business data")
	}
	backups, err := filepath.Glob(filepath.Join(dir, ".server-lock.stale-*.bak"))
	if err != nil || len(backups) != 1 {
		t.Fatalf("missing stale marker audit backup: %v %v", backups, err)
	}
	if backup, _ := os.ReadFile(backups[0]); !bytes.Equal(backup, marker) {
		t.Fatal("stale marker backup differs from original")
	}
}

func TestFileStoreDarwinRetainsLegacyActiveAndUnknownLocks(t *testing.T) {
	for name, marker := range map[string]string{
		"active-legacy":   fmt.Sprintf("pid=%d\nstarted=%s\n", os.Getpid(), timestamp(time.Now())),
		"empty":           "",
		"bad-pid":         "pid=0\nstarted=2026-11-04T00:00:00Z\n",
		"signed-pid":      "pid=+999999\nstarted=2026-11-04T00:00:00Z\n",
		"overflow-pid":    "pid=4294967295\nstarted=2026-11-04T00:00:00Z\n",
		"bad-time":        "pid=999999\nstarted=unknown\n",
		"missing-newline": "pid=999999\nstarted=2026-11-04T00:00:00Z",
		"extra-fields":    "pid=999999\nstarted=2026-11-04T00:00:00Z\nextra=value\n",
		"oversize":        strings.Repeat("x", 513),
	} {
		t.Run(name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, ".server-lock")
			if err := os.WriteFile(path, []byte(marker), 0600); err != nil {
				t.Fatal(err)
			}
			if store, err := OpenFileStore(dir); err == nil {
				store.Close()
				t.Fatal("accepted an active or unrecognized legacy marker")
			}
			if after, err := os.ReadFile(path); err != nil || string(after) != marker {
				t.Fatal("existing marker was changed", err)
			}
			if backups, _ := filepath.Glob(filepath.Join(dir, ".server-lock.stale-*.bak")); len(backups) != 0 {
				t.Fatal("created recovery backup without establishing a dead owner")
			}
		})
	}
}

func TestFileStoreDarwinRejectsSpecialLockFiles(t *testing.T) {
	for _, name := range []string{".server-lock", ".server-guard"} {
		for _, kind := range []string{"symlink", "directory", "fifo"} {
			t.Run(name+"/"+kind, func(t *testing.T) {
				dir := t.TempDir()
				path := filepath.Join(dir, name)
				target := filepath.Join(t.TempDir(), "untouched")
				if err := os.WriteFile(target, []byte("untouched"), 0600); err != nil {
					t.Fatal(err)
				}
				var err error
				switch kind {
				case "symlink":
					err = os.Symlink(target, path)
				case "directory":
					err = os.Mkdir(path, 0700)
				case "fifo":
					err = syscall.Mkfifo(path, 0600)
				}
				if err != nil {
					t.Fatal(err)
				}
				if store, err := OpenFileStore(dir); err == nil {
					store.Close()
					t.Fatal("accepted special lock file")
				}
				if _, err := os.Lstat(path); err != nil {
					t.Fatal("special lock file was removed", err)
				}
				if after, _ := os.ReadFile(target); string(after) != "untouched" {
					t.Fatal("symlink target was changed")
				}
			})
		}
	}
}

func TestFileStoreDarwinGuardPersistsAndOldCloseIsHarmless(t *testing.T) {
	dir := t.TempDir()
	first, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	guardPath := filepath.Join(dir, ".server-guard")
	before, err := os.Lstat(guardPath)
	if err != nil {
		t.Fatal(err)
	}
	first.Close()
	second, err := OpenFileStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	first.Close()
	after, err := os.Lstat(guardPath)
	if err != nil || !os.SameFile(before, after) {
		t.Fatal("guard inode changed across clean restart", err)
	}
	if _, err = os.Stat(filepath.Join(dir, ".server-lock")); err != nil {
		t.Fatal("repeated old Close removed the current server marker", err)
	}
	if other, err := OpenFileStore(dir); err == nil {
		other.Close()
		t.Fatal("repeated old Close released the current server guard")
	}
}
