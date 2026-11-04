// Created by Jobs on 2026年11月4日，星期三.
package platform

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Keep the exclusive marker protocol so older server binaries still exclude this one.
func createFileStoreMarker(dir string) (func(), error) {
	path := filepath.Join(dir, ".server-lock")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return nil, fmt.Errorf("data directory is already locked; existing .server-lock retained: %w", err)
	}
	info, statErr := f.Stat()
	contents := []byte(fmt.Sprintf("pid=%d\nstarted=%s\n", os.Getpid(), timestamp(time.Now())))
	_, writeErr := f.Write(contents)
	closeErr := f.Close()
	if err = errors.Join(statErr, writeErr, closeErr); err != nil {
		if statErr == nil {
			if current, e := os.Lstat(path); e == nil && os.SameFile(info, current) {
				_ = os.Remove(path)
			}
		}
		return nil, err
	}
	var once sync.Once
	return func() {
		once.Do(func() {
			current, e := os.Lstat(path)
			if e != nil || !current.Mode().IsRegular() || !os.SameFile(info, current) {
				return
			}
			b, e := os.ReadFile(path)
			if e == nil && bytes.Equal(b, contents) {
				_ = os.Remove(path)
			}
		})
	}, nil
}
