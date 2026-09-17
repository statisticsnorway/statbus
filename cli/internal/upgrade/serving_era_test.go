package upgrade

import (
	"errors"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

func servingEraExpected(sourceTag string) map[string]string {
	return map[string]string{
		"app":    "ghcr.io/statisticsnorway/statbus-app:" + sourceTag,
		"worker": "ghcr.io/statisticsnorway/statbus-worker:" + sourceTag,
		"rest":   "postgrest/postgrest:v12.2.8",
		"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:" + sourceTag,
	}
}

func servingEraEntries(images map[string]string) []compose.PsEntry {
	entries := make([]compose.PsEntry, 0, len(images))
	for _, service := range sourceServingServices {
		if image, ok := images[service]; ok {
			entries = append(entries, compose.PsEntry{Service: service, Image: image, State: "running"})
		}
	}
	return entries
}

func TestDeriveServingEraFromActualContainerImages(t *testing.T) {
	const sourceTag = "1234abcd"
	expected := servingEraExpected(sourceTag)

	tests := []struct {
		name       string
		images     map[string]string
		want       ServingEra
		wantErrSub string
	}{
		{
			name:   "all exact source images",
			images: expected,
			want:   ServingEraSource,
		},
		{
			name: "coherent target images",
			images: map[string]string{
				"app":    "ghcr.io/statisticsnorway/statbus-app:target99",
				"worker": "ghcr.io/statisticsnorway/statbus-worker:target99",
				"rest":   "postgrest/postgrest:v13",
				"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:target99",
			},
			want: ServingEraTarget,
		},
		{
			name: "target version with unchanged upstream rest",
			images: map[string]string{
				"app":    "ghcr.io/statisticsnorway/statbus-app:target99",
				"worker": "ghcr.io/statisticsnorway/statbus-worker:target99",
				"rest":   expected["rest"],
				"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:target99",
			},
			want: ServingEraTarget,
		},
		{
			name: "mixed source and target",
			images: map[string]string{
				"app":    expected["app"],
				"worker": "ghcr.io/statisticsnorway/statbus-worker:target99",
				"rest":   expected["rest"],
				"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:target99",
			},
			wantErrSub: "mixed source/target",
		},
		{
			name: "incoherent target tags",
			images: map[string]string{
				"app":    "ghcr.io/statisticsnorway/statbus-app:target99",
				"worker": "ghcr.io/statisticsnorway/statbus-worker:other999",
				"rest":   expected["rest"],
				"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:target99",
			},
			wantErrSub: "mixed non-source serving tags",
		},
		{
			name: "missing container",
			images: map[string]string{
				"app":    "ghcr.io/statisticsnorway/statbus-app:target99",
				"worker": "ghcr.io/statisticsnorway/statbus-worker:target99",
				"proxy":  "ghcr.io/statisticsnorway/statbus-proxy:target99",
			},
			wantErrSub: "rest container is missing",
		},
		{
			name: "source tag on wrong image repository",
			images: map[string]string{
				"app":    "evil.example/statbus-app:" + sourceTag,
				"worker": expected["worker"],
				"rest":   expected["rest"],
				"proxy":  expected["proxy"],
			},
			wantErrSub: "carries the source tag",
		},
		{
			name: "source tagged services with wrong rest",
			images: map[string]string{
				"app":    expected["app"],
				"worker": expected["worker"],
				"rest":   "postgrest/postgrest:v13",
				"proxy":  expected["proxy"],
			},
			wantErrSub: "rest image",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			era, err := deriveServingEra(servingEraEntries(tc.images), expected, sourceTag)
			if tc.wantErrSub == "" {
				if err != nil || era != tc.want {
					t.Fatalf("deriveServingEra = (%q, %v), want (%q, nil)", era, err, tc.want)
				}
				return
			}
			var eraErr *sourceServingEraUnknownError
			if !errors.As(err, &eraErr) || !strings.Contains(err.Error(), tc.wantErrSub) || era != "" {
				t.Fatalf("deriveServingEra = (%q, %T %v), want named refusal containing %q", era, err, err, tc.wantErrSub)
			}
		})
	}
}

func TestStartSourceApplicationStackDerivesEraAtItsBoundary(t *testing.T) {
	body := extractFuncBody(t, readUpgradeServiceSource(t), "func (d *Service) startSourceApplicationStack(")
	deriveIdx := strings.Index(body, "deriveServingEra(entries, expected, sourceTag)")
	if deriveIdx < 0 {
		t.Fatal("source-stack boundary no longer derives ServingEra from actual container images")
	}
	for _, required := range []string{
		"deriveServingEra(entries, expected, sourceTag)",
		"case ServingEraSource:",
		"case ServingEraTarget:",
		"deriveServingEra(postEntries, expected, sourceTag)",
		"postEra != ServingEraSource",
	} {
		if !strings.Contains(body, required) {
			t.Errorf("source-stack boundary lost explicit derived-era precondition %q", required)
		}
	}
	if strings.Contains(body[:deriveIdx], `"compose", "start"`) ||
		strings.Contains(body[:deriveIdx], `"compose", "up"`) {
		t.Fatal("source-stack boundary must derive an observed ServingEra before any start or recreate command")
	}
}
