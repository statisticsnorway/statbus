// logarchive.go — the upgrade/install LOG COMPANION that travels with a
// database dump (STATBUS-456).
//
// An upgrade log lives on the box's disk; the ledger row only carries its
// path (public.upgrade.log_relative_file_path). The moment a dump is taken
// somewhere else, every log reference dangles. The companion archive closes
// that gap: dbdumps/<stem>.pg_dump + dbdumps/<stem>.logs.tar.zst (gzip when
// the zstd binary is unavailable; the extension always matches the format
// actually written).
//
// Contents (member paths are rooted at the project dir):
//   - tmp/upgrade-logs/** — everything EXCEPT symlinks (the `latest`
//     convenience link would dangle on the restore side). This directory is
//     already bounded by pruneUpgradeLogs(20).
//   - tmp/install-logs/** — ONLY the files referenced by the dumped
//     database (public.upgrade.log_relative_file_path values starting with
//     "install-logs/", plus public.system_info's
//     install_last_log_relative_file_path), because that directory is
//     unbounded.
//
// Ordering invariant: the caller archives AFTER pg_dump succeeds, so the
// archive can only be newer than the rows — it never claims a log for a row
// the dump does not contain.
package dbdump

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

// Companion archive extensions. Preferred zstd first; FindLogsCompanion
// probes in this order.
const (
	LogsCompanionZstdExt = ".logs.tar.zst"
	LogsCompanionGzipExt = ".logs.tar.gz"
)

// ReferencedInstallLogsSQL selects every install-log reference the dumped
// database carries: public.upgrade rows whose log lives under
// tmp/install-logs/ (pre-A20 installs authored upgrade rows), plus the
// system_info pointer to the most recent ./sb install log. Values may be
// "install-logs/<name>" or a bare basename; normalizeInstallLogRef handles
// both. psql -At friendly: one value per line.
const ReferencedInstallLogsSQL = `
SELECT DISTINCT p FROM (
  SELECT log_relative_file_path AS p FROM public.upgrade
   WHERE log_relative_file_path LIKE 'install-logs/%'
  UNION ALL
  SELECT value AS p FROM public.system_info
   WHERE key = 'install_last_log_relative_file_path'
) s
WHERE p IS NOT NULL AND btrim(p) <> ''
ORDER BY 1
`

// LogsCompanionPathFor returns the companion path for a dump, given the
// compression actually used.
func LogsCompanionPathFor(dumpPath string, zstd bool) string {
	stem := strings.TrimSuffix(dumpPath, ".pg_dump")
	if zstd {
		return stem + LogsCompanionZstdExt
	}
	return stem + LogsCompanionGzipExt
}

// FindLogsCompanion returns the existing companion archive next to a dump,
// or "" when there is none.
func FindLogsCompanion(dumpPath string) string {
	stem := strings.TrimSuffix(dumpPath, ".pg_dump")
	for _, ext := range []string{LogsCompanionZstdExt, LogsCompanionGzipExt} {
		candidate := stem + ext
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			return candidate
		}
	}
	return ""
}

// zstdAvailable reports whether the zstd binary is on PATH. Compression is
// shelled out (no Go zstd dependency in go.mod); when absent the companion
// falls back to gzip and the extension reflects that.
func zstdAvailable() bool {
	_, err := exec.LookPath("zstd")
	return err == nil
}

// ReferencedInstallLogs asks the LOCAL database which install logs the
// (about to be dumped) rows reference. Returns the raw stored values;
// WriteLogsCompanion normalizes them. A query failure is returned — the
// caller decides whether it is fatal for the companion (it must never be
// fatal for the dump itself).
func ReferencedInstallLogs(projDir string) ([]string, error) {
	dbName, err := loadDbName(projDir)
	if err != nil {
		return nil, err
	}
	c, buildErr := compose.CommandContext(context.Background(), projDir, "exec", "-T", "db",
		"psql", "-U", "postgres", "-d", dbName, "-At", "-c", ReferencedInstallLogsSQL)
	if buildErr != nil {
		return nil, fmt.Errorf("construct install-log reference query: %w", buildErr)
	}
	out, err := c.Output()
	if err != nil {
		return nil, fmt.Errorf("query referenced install logs: %w", err)
	}
	var refs []string
	for _, line := range strings.Split(string(out), "\n") {
		if v := strings.TrimSpace(line); v != "" {
			refs = append(refs, v)
		}
	}
	return refs, nil
}

// normalizeInstallLogRef converts a DB-stored install-log reference to a safe
// basename under tmp/install-logs/. Stored shapes seen in the fleet:
// "install-logs/<name>" (public.upgrade rows), bare "<name>"
// (system_info). ok is false for anything else — empty values, absolute
// paths, or any traversal attempt never reach the archive.
func normalizeInstallLogRef(ref string) (name string, ok bool) {
	ref = strings.TrimSpace(ref)
	ref = strings.TrimPrefix(ref, "tmp/install-logs/")
	ref = strings.TrimPrefix(ref, "install-logs/")
	if ref == "" || ref == "." || ref == ".." {
		return "", false
	}
	if strings.ContainsAny(ref, "/\\") || strings.Contains(ref, "..") {
		return "", false
	}
	return ref, true
}

// companionMember is one file to archive: name is the tar member path
// (rooted at the project dir), absPath the on-disk source.
type companionMember struct {
	name    string
	absPath string
}

// collectLogsCompanionMembers builds the deterministic member set:
// tmp/upgrade-logs/** regular files (symlinks excluded — never ship a
// dangling link) plus the referenced tmp/install-logs/ files that actually
// exist. Missing directories are not an error.
func collectLogsCompanionMembers(projDir string, installLogRefs []string) []companionMember {
	members := map[string]companionMember{}

	upgradeDir := filepath.Join(projDir, "tmp", "upgrade-logs")
	_ = filepath.Walk(upgradeDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // best-effort: an unreadable entry is skipped, not fatal
		}
		if info.IsDir() || !info.Mode().IsRegular() {
			return nil // skip dirs and symlinks (latest et al.)
		}
		rel, err := filepath.Rel(projDir, path)
		if err != nil {
			return nil
		}
		members[filepath.ToSlash(rel)] = companionMember{name: filepath.ToSlash(rel), absPath: path}
		return nil
	})

	installDir := filepath.Join(projDir, "tmp", "install-logs")
	seenRefs := map[string]bool{}
	for _, ref := range installLogRefs {
		name, ok := normalizeInstallLogRef(ref)
		if !ok || seenRefs[name] {
			continue
		}
		seenRefs[name] = true
		absPath := filepath.Join(installDir, name)
		info, err := os.Stat(absPath) // Stat follows symlinks; a dangling ref is skipped
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		member := "tmp/install-logs/" + name
		members[member] = companionMember{name: member, absPath: absPath}
	}

	out := make([]companionMember, 0, len(members))
	for _, m := range members {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].name < out[j].name })
	return out
}

// WriteLogsCompanion writes the log companion archive beside dumpPath and
// returns its path and member file count. zstd when available, gzip
// otherwise — the returned path's extension matches the format written. An
// empty/missing log set is NOT an error: a valid empty archive is written
// and count is 0. The archive is committed atomically (.tmp → rename).
func WriteLogsCompanion(projDir, dumpPath string, installLogRefs []string) (path string, fileCount int, err error) {
	members := collectLogsCompanionMembers(projDir, installLogRefs)
	finalPath := LogsCompanionPathFor(dumpPath, zstdAvailable())
	tmpPath := finalPath + ".tmp"

	tmp, err := os.Create(tmpPath)
	if err != nil {
		return "", 0, fmt.Errorf("create temp companion archive: %w", err)
	}
	produceErr := writeCompressedTar(tmpPath, tmp, members)
	closeErr := tmp.Close()
	if produceErr != nil || closeErr != nil {
		_ = os.Remove(tmpPath) // best-effort cleanup of the partial archive
		if produceErr != nil {
			return "", 0, produceErr
		}
		return "", 0, fmt.Errorf("close temp companion archive: %w", closeErr)
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath) // best-effort cleanup
		return "", 0, fmt.Errorf("commit companion archive (rename .tmp): %w", err)
	}
	return finalPath, len(members), nil
}

// writeCompressedTar streams the members as a tar archive into out,
// compressed with the zstd binary when tmpPath ends in .zst, else gzip.
func writeCompressedTar(tmpPath string, out io.Writer, members []companionMember) error {
	if strings.HasSuffix(tmpPath, LogsCompanionZstdExt+".tmp") {
		zcmd := exec.Command("zstd", "-q", "-c")
		zcmd.Stdout = out
		zcmd.Stderr = os.Stderr
		stdin, err := zcmd.StdinPipe()
		if err != nil {
			return fmt.Errorf("pipe to zstd: %w", err)
		}
		if err := zcmd.Start(); err != nil {
			return fmt.Errorf("start zstd: %w", err)
		}
		twErr := writeTar(stdin, members)
		_ = stdin.Close()
		if err := zcmd.Wait(); err != nil {
			return fmt.Errorf("zstd compression failed: %w", err)
		}
		return twErr
	}

	gz := gzip.NewWriter(out)
	twErr := writeTar(gz, members)
	if err := gz.Close(); err != nil && twErr == nil {
		return fmt.Errorf("gzip close: %w", err)
	}
	return twErr
}

// writeTar writes every member as a regular-file tar entry. Member names are
// relative to the project dir (tmp/upgrade-logs/...), so extraction with -C
// <projDir> lands files exactly where a box keeps them.
func writeTar(w io.Writer, members []companionMember) error {
	tw := tar.NewWriter(w)
	for _, m := range members {
		info, err := os.Stat(m.absPath)
		if err != nil {
			return fmt.Errorf("stat %s: %w", m.absPath, err)
		}
		hdr, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return fmt.Errorf("tar header for %s: %w", m.absPath, err)
		}
		hdr.Name = m.name
		if err := tw.WriteHeader(hdr); err != nil {
			return fmt.Errorf("write tar header for %s: %w", m.name, err)
		}
		f, err := os.Open(m.absPath)
		if err != nil {
			return fmt.Errorf("open %s: %w", m.absPath, err)
		}
		_, copyErr := io.Copy(tw, f)
		closeErr := f.Close()
		if copyErr != nil {
			return fmt.Errorf("archive %s: %w", m.absPath, copyErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close %s: %w", m.absPath, closeErr)
		}
	}
	if err := tw.Close(); err != nil {
		return fmt.Errorf("finalize tar: %w", err)
	}
	return nil
}

// RestoreLogsCompanion unpacks the companion next to dumpPath into the
// project's tmp/, MERGING: existing unrelated files are left alone,
// same-named files are overwritten, nothing is deleted. found is false (and
// err nil) when no companion exists — absence is not an error. Extraction
// refuses absolute paths, traversal, and anything outside tmp/, and never
// recreates symlinks (the source archive excludes them, but a hand-crafted
// archive is untrusted input).
func RestoreLogsCompanion(projDir, dumpPath string) (found bool, fileCount int, err error) {
	companion := FindLogsCompanion(dumpPath)
	if companion == "" {
		return false, 0, nil
	}

	f, err := os.Open(companion)
	if err != nil {
		return true, 0, fmt.Errorf("open companion archive: %w", err)
	}
	defer func() { _ = f.Close() }()

	// Both branches below assign reader before it is used; declaring it here
	// without an initialiser keeps the linter honest about that.
	var reader io.Reader
	var zcmd *exec.Cmd
	if strings.HasSuffix(companion, LogsCompanionZstdExt) {
		if !zstdAvailable() {
			return true, 0, fmt.Errorf("companion is zstd-compressed but the zstd binary is not available — install zstd to unpack the logs (the database restore itself is unaffected)")
		}
		zcmd = exec.Command("zstd", "-d", "-q", "-c", companion)
		stdout, err := zcmd.StdoutPipe()
		if err != nil {
			return true, 0, fmt.Errorf("pipe from zstd: %w", err)
		}
		zcmd.Stderr = os.Stderr
		if err := zcmd.Start(); err != nil {
			return true, 0, fmt.Errorf("start zstd decompress: %w", err)
		}
		reader = stdout
	} else {
		gz, err := gzip.NewReader(f)
		if err != nil {
			return true, 0, fmt.Errorf("open gzip stream of companion: %w", err)
		}
		defer func() { _ = gz.Close() }()
		reader = gz
	}

	count, extractErr := extractTarMerging(projDir, reader)
	if zcmd != nil {
		if waitErr := zcmd.Wait(); waitErr != nil && extractErr == nil {
			extractErr = fmt.Errorf("zstd decompress failed: %w", waitErr)
		}
	}
	return true, count, extractErr
}

// extractTarMerging writes every regular-file member under projDir,
// merging. Returns the number of files written.
func extractTarMerging(projDir string, r io.Reader) (int, error) {
	tr := tar.NewReader(r)
	count := 0
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return count, fmt.Errorf("read companion archive: %w", err)
		}
		if hdr.Typeflag != tar.TypeReg {
			continue // never recreate symlinks/dirs/devices from an archive
		}
		name := filepath.Clean(hdr.Name)
		if filepath.IsAbs(name) || strings.HasPrefix(name, "..") {
			return count, fmt.Errorf("companion archive contains unsafe member path %q — refusing to extract", hdr.Name)
		}
		if name != "tmp" && !strings.HasPrefix(name, "tmp"+string(os.PathSeparator)) {
			return count, fmt.Errorf("companion archive member %q is outside tmp/ — refusing to extract", hdr.Name)
		}
		dest := filepath.Join(projDir, name)
		if err := os.MkdirAll(filepath.Dir(dest), 0755); err != nil {
			return count, fmt.Errorf("create directory for %s: %w", name, err)
		}
		out, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
		if err != nil {
			return count, fmt.Errorf("create %s: %w", name, err)
		}
		_, copyErr := io.Copy(out, tr)
		closeErr := out.Close()
		if copyErr != nil {
			return count, fmt.Errorf("write %s: %w", name, copyErr)
		}
		if closeErr != nil {
			return count, fmt.Errorf("close %s: %w", name, closeErr)
		}
		count++
	}
	return count, nil
}
