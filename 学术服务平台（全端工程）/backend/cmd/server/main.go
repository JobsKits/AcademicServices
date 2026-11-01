// Created by Jobs on 2026年10月30日，星期五.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"academic.local/platform/internal/platform"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
func run() error {
	c, err := platform.LoadConfig()
	if err != nil {
		return err
	}
	var store platform.Store
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if c.DatabaseURL != "" {
		store, err = platform.OpenPGStore(ctx, c.DatabaseURL)
	} else {
		store, err = platform.OpenFileStore(c.DataDir)
	}
	if err != nil {
		return err
	}
	defer store.Close()
	api := platform.NewAPI(platform.NewEngine(store), c)
	server := &http.Server{Addr: c.Listen, Handler: api, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 << 10}
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(done)
	go func() {
		<-done
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	slog.Info("academic service ready", "listen", c.Listen, "environment", c.Environment, "storage_postgres", c.DatabaseURL != "", "payment_mode", "manual_ledger")
	if c.Environment != "production" {
		slog.Warn("development sample identities enabled; configure passwords before production")
	}
	err = server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
