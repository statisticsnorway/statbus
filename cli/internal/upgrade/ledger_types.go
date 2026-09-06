package upgrade

import "fmt"

type UpgradeState string

const (
	UpgradeStateAvailable  UpgradeState = "available"
	UpgradeStateScheduled  UpgradeState = "scheduled"
	UpgradeStateInProgress UpgradeState = "in_progress"
	UpgradeStateCompleted  UpgradeState = "completed"
	UpgradeStateFailed     UpgradeState = "failed"
	UpgradeStateRolledBack UpgradeState = "rolled_back"
	UpgradeStateDismissed  UpgradeState = "dismissed"
	UpgradeStateSkipped    UpgradeState = "skipped"
	UpgradeStateSuperseded UpgradeState = "superseded"
)

var allUpgradeStates = []UpgradeState{
	UpgradeStateAvailable, UpgradeStateScheduled, UpgradeStateInProgress,
	UpgradeStateCompleted, UpgradeStateFailed, UpgradeStateRolledBack,
	UpgradeStateDismissed, UpgradeStateSkipped, UpgradeStateSuperseded,
}

func ParseUpgradeState(value string) (UpgradeState, error) {
	state := UpgradeState(value)
	switch state {
	case UpgradeStateAvailable, UpgradeStateScheduled, UpgradeStateInProgress,
		UpgradeStateCompleted, UpgradeStateFailed, UpgradeStateRolledBack,
		UpgradeStateDismissed, UpgradeStateSkipped, UpgradeStateSuperseded:
		return state, nil
	default:
		return "", fmt.Errorf("invalid upgrade state %q", value)
	}
}

func (state UpgradeState) String() string { return string(state) }

type ReleaseStatus string

const (
	ReleaseStatusCommit     ReleaseStatus = "commit"
	ReleaseStatusPrerelease ReleaseStatus = "prerelease"
	ReleaseStatusRelease    ReleaseStatus = "release"
)

var allReleaseStatuses = []ReleaseStatus{
	ReleaseStatusCommit, ReleaseStatusPrerelease, ReleaseStatusRelease,
}

func ParseReleaseStatus(value string) (ReleaseStatus, error) {
	status := ReleaseStatus(value)
	switch status {
	case ReleaseStatusCommit, ReleaseStatusPrerelease, ReleaseStatusRelease:
		return status, nil
	default:
		return "", fmt.Errorf("invalid release status %q", value)
	}
}

func (status ReleaseStatus) String() string { return string(status) }

type DockerImagesStatus string

const (
	DockerImagesStatusBuilding DockerImagesStatus = "building"
	DockerImagesStatusReady    DockerImagesStatus = "ready"
	DockerImagesStatusFailed   DockerImagesStatus = "failed"
)

var allDockerImagesStatuses = []DockerImagesStatus{
	DockerImagesStatusBuilding, DockerImagesStatusReady, DockerImagesStatusFailed,
}

func ParseDockerImagesStatus(value string) (DockerImagesStatus, error) {
	status := DockerImagesStatus(value)
	switch status {
	case DockerImagesStatusBuilding, DockerImagesStatusReady, DockerImagesStatusFailed:
		return status, nil
	default:
		return "", fmt.Errorf("invalid docker images status %q", value)
	}
}

func (status DockerImagesStatus) String() string { return string(status) }

type ReleaseBuildsStatus string

const (
	ReleaseBuildsStatusBuilding ReleaseBuildsStatus = "building"
	ReleaseBuildsStatusReady    ReleaseBuildsStatus = "ready"
	ReleaseBuildsStatusFailed   ReleaseBuildsStatus = "failed"
)

var allReleaseBuildsStatuses = []ReleaseBuildsStatus{
	ReleaseBuildsStatusBuilding, ReleaseBuildsStatusReady, ReleaseBuildsStatusFailed,
}

func ParseReleaseBuildsStatus(value string) (ReleaseBuildsStatus, error) {
	status := ReleaseBuildsStatus(value)
	switch status {
	case ReleaseBuildsStatusBuilding, ReleaseBuildsStatusReady, ReleaseBuildsStatusFailed:
		return status, nil
	default:
		return "", fmt.Errorf("invalid release builds status %q", value)
	}
}

func (status ReleaseBuildsStatus) String() string { return string(status) }
