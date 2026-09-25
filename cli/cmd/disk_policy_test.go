package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/diskpolicy"
)

// installerDiskLocations models the two paths passed by the install preflight.
func installerDiskLocations(t *testing.T) []diskpolicy.Measurement {
	t.Helper()
	root := t.TempDir()
	docker := filepath.Join(root, "docker-data")
	backups := filepath.Join(root, "statbus-backups")
	for _, path := range []string{docker, backups} {
		if err := os.Mkdir(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	var measurements []diskpolicy.Measurement
	for _, path := range []string{docker, backups} {
		measurement, err := diskpolicy.Measure(path)
		if err != nil {
			t.Fatal(err)
		}
		if measurement.Path != path {
			t.Fatalf("measured %q rather than %q", measurement.Path, path)
		}
		measurements = append(measurements, measurement)
	}
	return measurements
}

func TestDiskPolicyBelowMinimum(t *testing.T) {
	command := "curl -fsSL https://statbus.org/install.sh | env STATBUS_ENV_CONFIG=/home/operator/answers bash -s -- --channel prerelease --non-interactive"
	t.Setenv("STATBUS_INSTALL_RERUN_COMMAND", command)
	for _, measurement := range installerDiskLocations(t) {
		measurement.FreeGB = 19
		message, continueInstall := diskpolicy.Evaluate(measurement)
		if continueInstall {
			t.Fatalf("installation continued at %s: %s", measurement.Path, message)
		}
		for _, wanted := range []string{measurement.Path, "19 GB free", "at least 20 GB", command} {
			if !strings.Contains(message, wanted) {
				t.Errorf("refusal %q missing %q", message, wanted)
			}
		}
	}
}

func TestDiskPolicyWarningBand(t *testing.T) {
	for _, measurement := range installerDiskLocations(t) {
		for _, free := range []uint64{20, 39} {
			measurement.FreeGB = free
			message, continueInstall := diskpolicy.Evaluate(measurement)
			if !continueInstall || !strings.Contains(message, "40 GB is recommended") || !strings.Contains(message, measurement.Path) {
				t.Errorf("%d GB on %s: continued=%t message=%q", free, measurement.Path, continueInstall, message)
			}
		}
	}
}

func TestDiskPolicyRecommendedBand(t *testing.T) {
	for _, measurement := range installerDiskLocations(t) {
		for _, free := range []uint64{40, 80} {
			measurement.FreeGB = free
			message, continueInstall := diskpolicy.Evaluate(measurement)
			if !continueInstall || !strings.Contains(message, "recommendation is met") || !strings.Contains(message, measurement.Path) {
				t.Errorf("%d GB on %s: continued=%t message=%q", free, measurement.Path, continueInstall, message)
			}
		}
	}
}
