//go:build !darwin

// Created by Jobs on 2026年11月4日，星期三.
package platform

// Other systems retain the existing exclusive marker behavior.
func acquireFileStoreLock(dir string) (func(), error) {
	return createFileStoreMarker(dir)
}
