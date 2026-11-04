// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// The guard is never unlinked: all new servers must lock the same inode, even after a crash.
func acquireFileStoreLock(dir string) (func(), error) {
	path := filepath.Join(dir, ".server-guard")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0600)
	if err != nil {
		return nil, fmt.Errorf("cannot open data directory guard; existing guard retained: %w", err)
	}
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		f.Close()
		return nil, fmt.Errorf("refuse non-regular data directory guard: %s", path)
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, fmt.Errorf("data directory is already locked by another running server; guard retained: %w", err)
	}
	unlock := func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}
	current, err := os.Lstat(path)
	if err != nil || !current.Mode().IsRegular() || !os.SameFile(info, current) {
		unlock()
		return nil, errors.New("data directory guard changed during acquisition; existing files retained")
	}
	if err = recoverStaleFileStoreMarker(dir); err != nil {
		unlock()
		return nil, err
	}
	releaseMarker, err := createFileStoreMarker(dir)
	if err != nil {
		unlock()
		return nil, err
	}
	var once sync.Once
	return func() {
		once.Do(func() {
			releaseMarker()
			unlock()
		})
	}, nil
}

// Only a complete legacy marker whose recorded process no longer exists may be recovered.
func recoverStaleFileStoreMarker(dir string) error {
	path := filepath.Join(dir, ".server-lock")
	info, err := os.Lstat(path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Size() > 512 {
		return errors.New("refuse non-regular or invalid .server-lock; existing lock retained")
	}
	contents, err := readFileStoreMarker(path, info)
	if err != nil {
		return err
	}
	lines := strings.Split(string(contents), "\n")
	if len(lines) != 3 || lines[2] != "" || !strings.HasPrefix(lines[0], "pid=") || !strings.HasPrefix(lines[1], "started=") {
		return errors.New("cannot establish .server-lock ownership; existing lock retained")
	}
	pidText := strings.TrimPrefix(lines[0], "pid=")
	pid, err := strconv.Atoi(pidText)
	if err != nil || pid <= 0 || pid > 1<<31-1 || strconv.Itoa(pid) != pidText {
		return errors.New("invalid .server-lock process ID; existing lock retained")
	}
	if _, err = time.Parse(time.RFC3339Nano, strings.TrimPrefix(lines[1], "started=")); err != nil {
		return errors.New("invalid .server-lock start time; existing lock retained")
	}
	if err = syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
		return fmt.Errorf("data directory is already locked or process ownership is unknown (pid=%d); existing .server-lock retained", pid)
	}
	backup, err := os.CreateTemp(dir, ".server-lock.stale-*.bak")
	if err != nil {
		return fmt.Errorf("cannot back up stale .server-lock; existing lock retained: %w", err)
	}
	_, writeErr := backup.Write(contents)
	syncErr := backup.Sync()
	closeErr := backup.Close()
	if err = errors.Join(writeErr, syncErr, closeErr); err != nil {
		return fmt.Errorf("cannot finish stale .server-lock backup; existing lock retained: %w", err)
	}
	current, err := os.Lstat(path)
	if err != nil || !current.Mode().IsRegular() || !os.SameFile(info, current) {
		return errors.New(".server-lock identity changed during recovery; existing files retained")
	}
	latest, err := readFileStoreMarker(path, current)
	if err != nil || !bytes.Equal(contents, latest) || !errors.Is(syscall.Kill(pid, 0), syscall.ESRCH) {
		return errors.New(".server-lock contents or process ownership changed during recovery; existing files retained")
	}
	if err = os.Remove(path); err != nil {
		return fmt.Errorf("cannot remove backed-up stale .server-lock: %w", err)
	}
	slog.Warn("recovered stale data directory lock", "pid", pid, "backup", backup.Name())
	return nil
}

// Read the checked regular inode without following a substituted symlink or blocking on a FIFO.
func readFileStoreMarker(path string, expected os.FileInfo) ([]byte, error) {
	f, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || !os.SameFile(expected, info) {
		return nil, errors.New(".server-lock changed while reading; existing files retained")
	}
	contents, err := io.ReadAll(io.LimitReader(f, 513))
	if err != nil || len(contents) > 512 {
		return nil, errors.New("cannot read a valid .server-lock; existing lock retained")
	}
	return contents, nil
}
