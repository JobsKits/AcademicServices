//go:build windows

package main

import (
	"errors"
	"os/exec"
	"syscall"
	"unsafe"
)

var (
	kernel32       = syscall.NewLazyDLL("kernel32.dll")
	createJob      = kernel32.NewProc("CreateJobObjectW")
	setJobInfo     = kernel32.NewProc("SetInformationJobObject")
	assignJob      = kernel32.NewProc("AssignProcessToJobObject")
	terminateJob   = kernel32.NewProc("TerminateJobObject")
	threadSnapshot = kernel32.NewProc("CreateToolhelp32Snapshot")
	threadFirst    = kernel32.NewProc("Thread32First")
	threadNext     = kernel32.NewProc("Thread32Next")
	openThread     = kernel32.NewProc("OpenThread")
	resumeThread   = kernel32.NewProc("ResumeThread")
)

type processScope struct{ job syscall.Handle }
type jobBasicLimits struct {
	ProcessTime, JobTime                 int64
	Flags                                uint32
	MinimumWorkingSet, MaximumWorkingSet uintptr
	ActiveProcesses                      uint32
	Affinity                             uintptr
	Priority, Scheduling                 uint32
}
type jobLimits struct {
	Basic                                                      jobBasicLimits
	IO                                                         [6]uint64
	ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory uintptr
}
type threadEntry struct {
	Size, Usage, ID, Owner      uint32
	BasePriority, DeltaPriority int32
	Flags                       uint32
}

// 先以挂起态创建，再绑定独占Job；SDK不能抢在归属登记前派生进程。
func newProcessScope(cmd *exec.Cmd) (*processScope, error) {
	job, _, _ := createJob.Call(0, 0)
	if job == 0 {
		return nil, errors.New("无法创建本次依赖检查的Windows Job")
	}
	scope := &processScope{job: syscall.Handle(job)}
	limits := jobLimits{}
	limits.Basic.Flags = 0x2000 // KILL_ON_JOB_CLOSE
	ok, _, _ := setJobInfo.Call(job, 9, uintptr(unsafe.Pointer(&limits)), unsafe.Sizeof(limits))
	if ok == 0 {
		scope.close()
		return nil, errors.New("无法设置本次Windows Job回收边界")
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: 0x4 | 0x200} // CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP
	return scope, nil
}
func (s *processScope) attach(cmd *exec.Cmd) error {
	handle, err := syscall.OpenProcess(0x100|0x1|0x1000, false, uint32(cmd.Process.Pid))
	if err != nil {
		return errors.New("无法核对本次Go检查进程")
	}
	defer syscall.CloseHandle(handle)
	ok, _, _ := assignJob.Call(uintptr(s.job), uintptr(handle))
	if ok == 0 {
		return errors.New("无法把本次Go检查绑定Windows Job")
	}
	snapshot, _, _ := threadSnapshot.Call(0x4, 0) // TH32CS_SNAPTHREAD
	if snapshot == ^uintptr(0) {
		return errors.New("无法定位本次挂起的Go检查线程")
	}
	defer syscall.CloseHandle(syscall.Handle(snapshot))
	entry := threadEntry{Size: uint32(unsafe.Sizeof(threadEntry{}))}
	ok, _, _ = threadFirst.Call(snapshot, uintptr(unsafe.Pointer(&entry)))
	resumed := false
	for ok != 0 {
		if entry.Owner == uint32(cmd.Process.Pid) {
			thread, _, _ := openThread.Call(0x2, 0, uintptr(entry.ID)) // THREAD_SUSPEND_RESUME
			if thread == 0 {
				return errors.New("无法打开本次Go检查线程")
			}
			count, _, _ := resumeThread.Call(thread)
			syscall.CloseHandle(syscall.Handle(thread))
			if uint32(count) == 0xffffffff {
				return errors.New("无法恢复本次Go检查线程")
			}
			resumed = true
		}
		entry.Size = uint32(unsafe.Sizeof(entry))
		ok, _, _ = threadNext.Call(snapshot, uintptr(unsafe.Pointer(&entry)))
	}
	if !resumed {
		return errors.New("未找到本次Go检查线程")
	}
	return nil
}
func (s *processScope) kill(_ *exec.Cmd) error {
	ok, _, _ := terminateJob.Call(uintptr(s.job), 1)
	if ok == 0 {
		return errors.New("本次Windows依赖检查进程树回收失败")
	}
	return nil
}
func (s *processScope) close() {
	if s.job != 0 {
		syscall.CloseHandle(s.job)
		s.job = 0
	}
}
