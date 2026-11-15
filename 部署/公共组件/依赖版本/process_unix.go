//go:build !windows

package main

import (
	"os/exec"
	"syscall"
)

type processScope struct{}

func newProcessScope(cmd *exec.Cmd) (*processScope, error) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return &processScope{}, nil
}
func (*processScope) attach(_ *exec.Cmd) error { return nil }
func (*processScope) kill(cmd *exec.Cmd) error {
	if cmd.Process == nil {
		return nil
	}
	err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	if err == syscall.ESRCH {
		return nil
	}
	return err
}
func (*processScope) close() {}
