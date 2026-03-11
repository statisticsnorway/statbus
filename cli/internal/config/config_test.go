package config

import (
	"testing"
)

func TestParseMemSizeToMB(t *testing.T) {
	tests := []struct {
		input string
		want  int64
	}{
		{"4G", 4096},
		{"8G", 8192},
		{"1G", 1024},
		{"512M", 512},
		{"256M", 256},
		{"1024K", 1},
		{"2g", 2048}, // uppercase conversion
	}
	for _, tt := range tests {
		got, err := parseMemSizeToMB(tt.input)
		if err != nil {
			t.Errorf("parseMemSizeToMB(%q) error: %v", tt.input, err)
			continue
		}
		if got != tt.want {
			t.Errorf("parseMemSizeToMB(%q) = %d, want %d", tt.input, got, tt.want)
		}
	}
}

func TestFormatMBForPG(t *testing.T) {
	tests := []struct {
		input int64
		want  string
	}{
		{1024, "1GB"},
		{2048, "2GB"},
		{512, "512MB"},
		{4096, "4GB"},
		{1536, "1536MB"}, // not evenly divisible by 1024
	}
	for _, tt := range tests {
		got := formatMBForPG(tt.input)
		if got != tt.want {
			t.Errorf("formatMBForPG(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestFormatMBForDocker(t *testing.T) {
	tests := []struct {
		input int64
		want  string
	}{
		{1024, "1G"},
		{2048, "2G"},
		{512, "512M"},
		{4096, "4G"},
	}
	for _, tt := range tests {
		got := formatMBForDocker(tt.input)
		if got != tt.want {
			t.Errorf("formatMBForDocker(%d) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestComputeDbMemory4G(t *testing.T) {
	mem, err := computeDbMemory("4G")
	if err != nil {
		t.Fatal(err)
	}

	// 4G = 4096MB
	// shared_buffers: 25% = 1024MB = 1GB
	assertStr(t, "DbSharedBuffers", mem.DbSharedBuffers, "1GB")
	// effective_cache_size: 75% = 3072MB = 3GB
	assertStr(t, "DbEffectiveCacheSize", mem.DbEffectiveCacheSize, "3GB")
	// maintenance_work_mem: min(2048, 12.5%) = 512MB
	assertStr(t, "DbMaintenanceWorkMem", mem.DbMaintenanceWorkMem, "512MB")
	// work_mem: 4096/32 = 128MB
	assertStr(t, "DbWorkMem", mem.DbWorkMem, "128MB")
	// temp_buffers: max(256, 4096/8) = 512MB
	assertStr(t, "DbTempBuffers", mem.DbTempBuffers, "512MB")
	// wal_buffers: min(256, max(16, 4096*0.015=61)) = 61MB
	assertStr(t, "DbWalBuffers", mem.DbWalBuffers, "61MB")
	// max_connections: always 30
	if mem.DbMaxConnections != 30 {
		t.Errorf("DbMaxConnections = %d, want 30", mem.DbMaxConnections)
	}
	// max_wal_size: max(2048, 4096/2) = 2048
	assertStr(t, "DbMaxWalSize", mem.DbMaxWalSize, "2GB")
	// min_wal_size: max(256, 4096/8) = 512MB
	assertStr(t, "DbMinWalSize", mem.DbMinWalSize, "512MB")
	// shm_size: lowercase
	assertStr(t, "DbShmSize", mem.DbShmSize, "4g")
	// reservation: 4096/2 = 2048 = 2G
	assertStr(t, "DbMemReservation", mem.DbMemReservation, "2G")
}

func TestComputeDbMemory8G(t *testing.T) {
	mem, err := computeDbMemory("8G")
	if err != nil {
		t.Fatal(err)
	}

	// 8G = 8192MB
	assertStr(t, "DbSharedBuffers", mem.DbSharedBuffers, "2GB")
	assertStr(t, "DbEffectiveCacheSize", mem.DbEffectiveCacheSize, "6GB")
	assertStr(t, "DbMaintenanceWorkMem", mem.DbMaintenanceWorkMem, "1GB")
	assertStr(t, "DbWorkMem", mem.DbWorkMem, "256MB")
	assertStr(t, "DbTempBuffers", mem.DbTempBuffers, "1GB")
	assertStr(t, "DbWalBuffers", mem.DbWalBuffers, "122MB")
	assertStr(t, "DbMaxWalSize", mem.DbMaxWalSize, "4GB")
	assertStr(t, "DbMinWalSize", mem.DbMinWalSize, "1GB")
}

func TestComputeDerivedDevelopment(t *testing.T) {
	cfg := &ConfigEnv{
		DeploymentSlotCode:       "local",
		DeploymentSlotName:       "local",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:     "development",
		SiteDomain:               "local.statbus.org",
		StatbusURL:               "http://localhost:3010",
		BrowserAPIURL:            "http://local.statbus.org:3010",
	}

	d := computeDerived(cfg)

	// Port offset 1: base 3000 + (1*10) = 3010
	if d.CaddyHttpPort != 3010 {
		t.Errorf("CaddyHttpPort = %d, want 3010", d.CaddyHttpPort)
	}
	if d.CaddyHttpsPort != 3011 {
		t.Errorf("CaddyHttpsPort = %d, want 3011", d.CaddyHttpsPort)
	}
	if d.AppPort != 3012 {
		t.Errorf("AppPort = %d, want 3012", d.AppPort)
	}
	if d.PostgrestPort != 3013 {
		t.Errorf("PostgrestPort = %d, want 3013", d.PostgrestPort)
	}
	if d.CaddyDbPort != 3014 {
		t.Errorf("CaddyDbPort = %d, want 3014", d.CaddyDbPort)
	}
	if d.CaddyDbTlsPort != 3015 {
		t.Errorf("CaddyDbTlsPort = %d, want 3015", d.CaddyDbTlsPort)
	}
	if d.CaddyHttpBindAddress != "127.0.0.1:3010" {
		t.Errorf("CaddyHttpBindAddress = %q, want 127.0.0.1:3010", d.CaddyHttpBindAddress)
	}
	if d.DeploymentUser != "statbus_local" {
		t.Errorf("DeploymentUser = %q, want statbus_local", d.DeploymentUser)
	}
}

func TestComputeDerivedStandalone(t *testing.T) {
	cfg := &ConfigEnv{
		DeploymentSlotCode:       "mw",
		DeploymentSlotName:       "Malawi Statistics",
		DeploymentSlotPortOffset: "1",
		CaddyDeploymentMode:     "standalone",
		SiteDomain:               "statbus.nso.mw",
	}

	d := computeDerived(cfg)

	if d.CaddyHttpPort != 80 {
		t.Errorf("CaddyHttpPort = %d, want 80", d.CaddyHttpPort)
	}
	if d.CaddyHttpsPort != 443 {
		t.Errorf("CaddyHttpsPort = %d, want 443", d.CaddyHttpsPort)
	}
	if d.CaddyDbPort != 5431 {
		t.Errorf("CaddyDbPort = %d, want 5431", d.CaddyDbPort)
	}
	if d.CaddyDbTlsPort != 5432 {
		t.Errorf("CaddyDbTlsPort = %d, want 5432", d.CaddyDbTlsPort)
	}
	if d.CaddyHttpBindAddress != "0.0.0.0:80" {
		t.Errorf("CaddyHttpBindAddress = %q, want 0.0.0.0:80", d.CaddyHttpBindAddress)
	}
	if d.CaddyDbBindAddress != "127.0.0.1" {
		t.Errorf("CaddyDbBindAddress = %q, want 127.0.0.1", d.CaddyDbBindAddress)
	}
	if d.CaddyDbTlsBindAddress != "0.0.0.0" {
		t.Errorf("CaddyDbTlsBindAddress = %q, want 0.0.0.0", d.CaddyDbTlsBindAddress)
	}
}

func TestProjectDir(t *testing.T) {
	// Just verify it doesn't panic
	dir := ProjectDir()
	if dir == "" {
		t.Error("ProjectDir returned empty string")
	}
}

func assertStr(t *testing.T, name, got, want string) {
	t.Helper()
	if got != want {
		t.Errorf("%s = %q, want %q", name, got, want)
	}
}
