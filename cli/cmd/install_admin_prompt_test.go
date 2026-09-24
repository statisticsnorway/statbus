package cmd

import "testing"

func TestPasswordMismatchRetriesWithoutDisclosure(t *testing.T) {
	answers := []string{"first-secret", "different-secret", "matching-secret", "matching-secret"}
	i := 0
	value, err := askAdministratorPassword(func(string) (string, error) { answer := answers[i]; i++; return answer, nil })
	if err != nil || value != "matching-secret" || i != 4 {
		t.Fatalf("retry failed, err=%v, reads=%d", err, i)
	}
}
