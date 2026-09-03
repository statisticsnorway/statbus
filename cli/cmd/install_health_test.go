package cmd

import "testing"

func TestClassifyDockerHealth(t *testing.T) {
	tests := []struct {
		name      string
		raw       string
		want      dockerHealth
		wantReady bool
		wantErr   bool
	}{
		{name: "healthy", raw: "healthy\n", want: dockerHealthHealthy, wantReady: true},
		{name: "unhealthy", raw: "unhealthy\n", want: dockerHealthUnhealthy},
		{name: "starting", raw: "starting\n", want: dockerHealthStarting},
		{name: "empty", raw: "\n", want: dockerHealthAbsent},
		{name: "unknown refuses", raw: "paused\n", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := classifyDockerHealth(tt.raw)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("classifyDockerHealth(%q) error = nil, want refusal", tt.raw)
				}
				return
			}
			if err != nil {
				t.Fatalf("classifyDockerHealth(%q): %v", tt.raw, err)
			}
			if got != tt.want {
				t.Errorf("classifyDockerHealth(%q) = %v, want %v", tt.raw, got, tt.want)
			}
			if got.ready() != tt.wantReady {
				t.Errorf("classifyDockerHealth(%q).ready() = %v, want %v", tt.raw, got.ready(), tt.wantReady)
			}
		})
	}
}
