package cmd

import (
	"crypto/x509"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// The Linux trust-store locations Go itself reads (crypto/x509 root_linux.go
// and root_unix.go), so a fresh read sees exactly what x509.SystemCertPool
// would have seen had it been read now. update-ca-certificates writes the
// first file on Debian and Ubuntu.
var linuxCertFiles = []string{
	"/etc/ssl/certs/ca-certificates.crt",
	"/etc/pki/tls/certs/ca-bundle.crt",
	"/etc/ssl/ca-bundle.pem",
	"/etc/pki/tls/cacert.pem",
	"/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem",
	"/etc/ssl/cert.pem",
}

var linuxCertDirectories = []string{"/etc/ssl/certs", "/etc/pki/tls/certs"}

// currentSystemRoots reads the system trust store as it is now (see
// visitSystemRoots). Off Linux, where the installer does not run, it falls
// back to the platform's cached pool.
func currentSystemRoots() (*x509.CertPool, error) {
	if runtime.GOOS != "linux" {
		return x509.SystemCertPool()
	}
	roots := x509.NewCertPool()
	files := linuxCertFiles
	if f := os.Getenv("SSL_CERT_FILE"); f != "" {
		files = []string{f}
	}
	var firstErr error
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err == nil {
			roots.AppendCertsFromPEM(data)
			break
		}
		if firstErr == nil && !os.IsNotExist(err) {
			firstErr = err
		}
	}
	dirs := linuxCertDirectories
	if d := os.Getenv("SSL_CERT_DIR"); d != "" {
		dirs = strings.Split(d, ":")
	}
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			if firstErr == nil && !os.IsNotExist(err) {
				firstErr = err
			}
			continue
		}
		for _, entry := range entries {
			if data, err := os.ReadFile(filepath.Join(dir, entry.Name())); err == nil {
				roots.AppendCertsFromPEM(data)
			}
		}
	}
	if len(roots.Subjects()) > 0 || firstErr == nil { //nolint:staticcheck // Subjects only counts; system pools are not used here.
		return roots, nil
	}
	return nil, firstErr
}
