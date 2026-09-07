package upgrade

import "fmt"

type UpgradeFailureCode string

const (
	ErrMigrationFailed            UpgradeFailureCode = "MIGRATION_FAILED"
	ErrBackupFailed               UpgradeFailureCode = "BACKUP_FAILED"
	ErrDockerUpFailed             UpgradeFailureCode = "DOCKER_UP_FAILED"
	ErrHealthcheckRESTDown        UpgradeFailureCode = "HEALTHCHECK_REST_DOWN"
	ErrHealthcheckAppDown         UpgradeFailureCode = "HEALTHCHECK_APP_DOWN"
	ErrHealthcheckDBDown          UpgradeFailureCode = "HEALTHCHECK_DB_DOWN"
	ErrRollbackGitCorrupt         UpgradeFailureCode = "ROLLBACK_FAILED_GIT_CORRUPT"
	ErrRollbackDBRestore          UpgradeFailureCode = "ROLLBACK_FAILED_DB_RESTORE"
	ErrUpgradeStoppedUnchanged    UpgradeFailureCode = "UPGRADE_STOPPED_NOTHING_CHANGED"
	ErrRollbackServicesUp         UpgradeFailureCode = "ROLLBACK_FAILED_SERVICES_UP"
	ErrRollbackServicesNotStopped UpgradeFailureCode = "ROLLBACK_FAILED_SERVICES_NOT_STOPPED"
	ErrRollbackBinaryCorrupt      UpgradeFailureCode = "ROLLBACK_FAILED_BINARY_CORRUPT"
	ErrBinaryReplaceFailed        UpgradeFailureCode = "BINARY_REPLACE_FAILED"
	ErrBinaryBuildFailed          UpgradeFailureCode = "BINARY_BUILD_FAILED"
	ErrInstallFixupFailed         UpgradeFailureCode = "INSTALL_FIXUP_FAILED"
	ErrGitFetchRetryable          UpgradeFailureCode = "GIT_FETCH_FAILED_RETRYABLE"
	ErrInstallPreconditionFailed  UpgradeFailureCode = "INSTALL_PRECONDITION_FAILED"
	ErrRollbackSchemaFloorFailed  UpgradeFailureCode = "ROLLBACK_SCHEMA_FLOOR_FAILED"
)

var allUpgradeFailureCodes = []UpgradeFailureCode{
	ErrMigrationFailed, ErrBackupFailed, ErrDockerUpFailed,
	ErrHealthcheckRESTDown, ErrHealthcheckAppDown, ErrHealthcheckDBDown,
	ErrRollbackGitCorrupt, ErrRollbackDBRestore, ErrUpgradeStoppedUnchanged,
	ErrRollbackServicesUp, ErrRollbackServicesNotStopped, ErrRollbackBinaryCorrupt,
	ErrBinaryReplaceFailed, ErrBinaryBuildFailed, ErrInstallFixupFailed,
	ErrGitFetchRetryable, ErrInstallPreconditionFailed,
	ErrRollbackSchemaFloorFailed,
}

func ParseUpgradeFailureCode(value string) (UpgradeFailureCode, error) {
	code := UpgradeFailureCode(value)
	switch code {
	case ErrMigrationFailed,
		ErrBackupFailed,
		ErrDockerUpFailed,
		ErrHealthcheckRESTDown,
		ErrHealthcheckAppDown,
		ErrHealthcheckDBDown,
		ErrRollbackGitCorrupt,
		ErrRollbackDBRestore,
		ErrUpgradeStoppedUnchanged,
		ErrRollbackServicesUp,
		ErrRollbackServicesNotStopped,
		ErrRollbackBinaryCorrupt,
		ErrBinaryReplaceFailed,
		ErrBinaryBuildFailed,
		ErrInstallFixupFailed,
		ErrGitFetchRetryable,
		ErrInstallPreconditionFailed,
		ErrRollbackSchemaFloorFailed:
		return code, nil
	default:
		return "", fmt.Errorf("unknown upgrade failure code %q", value)
	}
}

func ptrFailureCode(code UpgradeFailureCode) *UpgradeFailureCode {
	return &code
}

func (code UpgradeFailureCode) String() string { return string(code) }
