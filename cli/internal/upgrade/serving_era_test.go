package upgrade

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/statisticsnorway/statbus/cli/internal/compose"
)

func servingEraTestImageID(hexDigit byte) string {
	return "sha256:" + strings.Repeat(string(hexDigit), 64)

}

func servingEraExpected(sourceTag string) map[string]sourceImageIdentity {
	return map[string]sourceImageIdentity{
		"app":    {Reference: "ghcr.io/statisticsnorway/statbus-app:" + sourceTag, ImageID: servingEraTestImageID('1')},
		"worker": {Reference: "ghcr.io/statisticsnorway/statbus-worker:" + sourceTag, ImageID: servingEraTestImageID('2')},
		"rest":   {Reference: "postgrest/postgrest:v12.2.8", ImageID: servingEraTestImageID('3')},
		"proxy":  {Reference: "ghcr.io/statisticsnorway/statbus-proxy:" + sourceTag, ImageID: servingEraTestImageID('4')},
	}
}

func servingEraEntries(images map[string]sourceImageIdentity) []compose.PsEntry {
	entries := make([]compose.PsEntry, 0, len(images))
	for _, service := range sourceServingServices {
		if image, ok := images[service]; ok {
			entries = append(entries, compose.PsEntry{Service: service, Image: image.Reference, ImageID: image.ImageID, State: "running"})
		}
	}
	return entries
}

func targetServingIdentities(tag string) map[string]sourceImageIdentity {
	return map[string]sourceImageIdentity{
		"app":    {Reference: "ghcr.io/statisticsnorway/statbus-app:" + tag, ImageID: servingEraTestImageID('a')},
		"worker": {Reference: "ghcr.io/statisticsnorway/statbus-worker:" + tag, ImageID: servingEraTestImageID('b')},
		"rest":   {Reference: "postgrest/postgrest:v13", ImageID: servingEraTestImageID('c')},
		"proxy":  {Reference: "ghcr.io/statisticsnorway/statbus-proxy:" + tag, ImageID: servingEraTestImageID('d')},
	}
}

func TestDeriveServingEraFromActualContainerImages(t *testing.T) {
	const sourceTag = "1234abcd"
	expected := servingEraExpected(sourceTag)

	tests := []struct {
		name       string
		images     map[string]sourceImageIdentity
		want       ServingEra
		wantErrSub string
	}{
		{
			name:   "all exact source images",
			images: expected,
			want:   ServingEraSource,
		},
		{
			name:   "coherent target images",
			images: targetServingIdentities("target99"),
			want:   ServingEraTarget,
		},
		{
			name: "target version with unchanged upstream rest",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["rest"] = expected["rest"]
				return images
			}(),
			want: ServingEraTarget,
		},
		{
			name: "mixed source and target",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["app"] = expected["app"]
				images["rest"] = expected["rest"]
				return images
			}(),
			wantErrSub: "mixed source/target",
		},
		{
			name: "incoherent target tags",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				images["worker"] = sourceImageIdentity{Reference: "ghcr.io/statisticsnorway/statbus-worker:other999", ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "mixed non-source serving tags",
		},
		{
			name: "missing container",
			images: func() map[string]sourceImageIdentity {
				images := targetServingIdentities("target99")
				delete(images, "rest")
				return images
			}(),
			wantErrSub: "rest container is missing",
		},
		{
			name: "source tag on wrong image repository",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: "evil.example/statbus-app:" + sourceTag, ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "source-like tag",
		},
		{
			name: "source tagged services with wrong rest",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["rest"] = sourceImageIdentity{Reference: "postgrest/postgrest:v13", ImageID: servingEraTestImageID('c')}
				return images
			}(),
			wantErrSub: "rest immutable image ID",
		},
		{
			name: "same-short rebuild fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: expected["app"].Reference, ImageID: servingEraTestImageID('e')}
				return images
			}(),
			wantErrSub: "moving tag or same-short rebuild",
		},
		{
			name: "moving source tag fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["proxy"] = sourceImageIdentity{Reference: expected["proxy"].Reference, ImageID: servingEraTestImageID('f')}
				return images
			}(),
			wantErrSub: "moving tag or same-short rebuild",
		},
		{
			name: "unresolvable immutable identity fails closed",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: expected["app"].Reference}
				return images
			}(),
			wantErrSub: "no resolvable immutable image identity",
		},
		{
			name: "digest aliases with exact image IDs are source",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				images["app"] = sourceImageIdentity{Reference: "mirror.example/statbus-app@" + servingEraTestImageID('9'), ImageID: expected["app"].ImageID}
				return images
			}(),
			want: ServingEraSource,
		},
		{
			name: "local references use immutable IDs",
			images: func() map[string]sourceImageIdentity {
				images := maps.Clone(expected)
				for _, service := range sourceVersionTaggedServingServices {
					identity := images[service]
					identity.Reference = "ghcr.io/statisticsnorway/statbus-" + service + ":local"
					images[service] = identity
				}
				return images
			}(),
			want: ServingEraSource,
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

func TestSourceServingExpectedImageReferencesHandlesDigestAndLocal(t *testing.T) {
	git := newGitRepoFixture(t)
	digest := servingEraTestImageID('9')
	tests := []struct {
		name       string
		appRef     string
		workerRef  string
		proxyRef   string
		wantErrSub string
	}{
		{
			name:      "explicit local references",
			appRef:    "ghcr.io/statisticsnorway/statbus-app:local",
			workerRef: "ghcr.io/statisticsnorway/statbus-worker:local",
			proxyRef:  "ghcr.io/statisticsnorway/statbus-proxy:local",
		},
		{
			name:      "immutable digest references",
			appRef:    "ghcr.io/statisticsnorway/statbus-app@" + digest,
			workerRef: "ghcr.io/statisticsnorway/statbus-worker@" + digest,
			proxyRef:  "ghcr.io/statisticsnorway/statbus-proxy@" + digest,
		},
		{
			name:       "malformed digest fails closed",
			appRef:     "ghcr.io/statisticsnorway/statbus-app@sha256:not-a-digest",
			workerRef:  "ghcr.io/statisticsnorway/statbus-worker@" + digest,
			proxyRef:   "ghcr.io/statisticsnorway/statbus-proxy@" + digest,
			wantErrSub: "malformed digest reference",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			shimDir := t.TempDir()
			config := fmt.Sprintf(`{"services":{"app":{"image":%q},"worker":{"image":%q},"rest":{"image":"postgrest/postgrest:v12.2.8"},"proxy":{"image":%q}}}`, tc.appRef, tc.workerRef, tc.proxyRef)
			shim := "#!/bin/sh\ncase \"$*\" in\n  \"compose config --format json\") printf '%s\\n' '" + config + "' ;;\nesac\n"
			if err := os.WriteFile(filepath.Join(shimDir, "docker"), []byte(shim), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
			d := &Service{projDir: git.dir}
			references, _, err := d.sourceServingExpectedImageReferences(context.Background())
			if tc.wantErrSub != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErrSub) {
					t.Fatalf("source references error = %v, want %q", err, tc.wantErrSub)
				}
				return
			}
			if err != nil {
				t.Fatalf("sourceServingExpectedImageReferences: %v", err)
			}
			if references["app"] != tc.appRef || references["worker"] != tc.workerRef || references["proxy"] != tc.proxyRef {
				t.Fatalf("references = %#v, want app=%q worker=%q proxy=%q", references, tc.appRef, tc.workerRef, tc.proxyRef)
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
