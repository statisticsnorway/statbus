package monitor

import (
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

type exportedTemplate struct {
	Export struct {
		Version        string `yaml:"version"`
		TemplateGroups []struct {
			Name string `yaml:"name"`
		} `yaml:"template_groups"`
		Templates []struct {
			Template string `yaml:"template"`
			Groups   []struct {
				Name string `yaml:"name"`
			} `yaml:"groups"`
			Items []struct {
				Key        string `yaml:"key"`
				Type       string `yaml:"type"`
				ValueType  string `yaml:"value_type"`
				MasterItem struct {
					Key string `yaml:"key"`
				} `yaml:"master_item"`
				Preprocessing []struct {
					Type       string   `yaml:"type"`
					Parameters []string `yaml:"parameters"`
				} `yaml:"preprocessing"`
			} `yaml:"items"`
			Triggers []struct {
				Name       string `yaml:"name"`
				Expression string `yaml:"expression"`
				Priority   string `yaml:"priority"`
			} `yaml:"triggers"`
		} `yaml:"templates"`
	} `yaml:"zabbix_export"`
}

func TestZabbixTemplateParsesAsZabbix7Export(t *testing.T) {
	template := ZabbixTemplate()
	if !strings.Contains(template, "UserParameter=statbus.monitor,/home/statbus/statbus/sb monitor status --format json") {
		t.Fatal("header does not carry the UserParameter line")
	}
	var exported exportedTemplate
	if err := yaml.Unmarshal([]byte(template), &exported); err != nil {
		t.Fatalf("template is not valid YAML: %v", err)
	}
	if exported.Export.Version == "" {
		t.Fatal("missing zabbix_export.version")
	}
	if len(exported.Export.Templates) != 1 {
		t.Fatalf("templates = %d, want 1", len(exported.Export.Templates))
	}
	tmpl := exported.Export.Templates[0]
	if tmpl.Template != "StatBus" {
		t.Fatalf("template name = %q", tmpl.Template)
	}
	if len(tmpl.Groups) != 1 {
		t.Fatalf("template groups = %d, want 1", len(tmpl.Groups))
	}

	// The master item is the UserParameter command; every other item is a
	// dependent item that reads one JSON value from it.
	var master, dependents int
	checksSeen := map[string]bool{}
	for _, item := range tmpl.Items {
		switch item.Type {
		case "ZABBIX_PASSIVE":
			master++
			if item.Key != "statbus.monitor" {
				t.Errorf("master item key = %q", item.Key)
			}
		case "DEPENDENT":
			dependents++
			if item.MasterItem.Key != "statbus.monitor" {
				t.Errorf("dependent item %q master = %q", item.Key, item.MasterItem.Key)
			}
			if len(item.Preprocessing) == 0 || item.Preprocessing[0].Type != "JSONPATH" {
				t.Errorf("dependent item %q has no JSONPath preprocessing", item.Key)
			}
			for _, name := range []string{CheckServices, CheckAPI, CheckSite, CheckDisk, CheckBackups, CheckUpgrader, CheckWorker} {
				if item.Key == "statbus.check."+name {
					checksSeen[name] = true
				}
			}
		default:
			t.Errorf("item %q has type %q", item.Key, item.Type)
		}
	}
	if master != 1 {
		t.Fatalf("master items = %d, want 1", master)
	}
	if !checksSeen[CheckServices] || !checksSeen[CheckWorker] || len(checksSeen) != 7 {
		t.Fatalf("per-check dependent items = %v, want all seven", checksSeen)
	}
	if dependents != 2+len(checksSeen) {
		t.Fatalf("dependent items = %d, want %d", dependents, 2+len(checksSeen))
	}

	if len(tmpl.Triggers) == 0 {
		t.Fatal("no triggers")
	}
	var hasStatusTrigger, hasStaleTrigger bool
	for _, trigger := range tmpl.Triggers {
		if strings.Contains(trigger.Expression, "statbus.status") {
			hasStatusTrigger = true
		}
		if strings.Contains(trigger.Expression, "statbus.checked_at_unixtime") &&
			strings.Contains(trigger.Expression, ">300") {
			hasStaleTrigger = true
		}
		if trigger.Priority == "" {
			t.Errorf("trigger %q has no priority", trigger.Name)
		}
	}
	if !hasStatusTrigger {
		t.Error("no trigger on overall status")
	}
	if !hasStaleTrigger {
		t.Error("no trigger on a checked_at older than 5 minutes")
	}
}

func TestUptimeTemplateNamesTheSiteAndExpectedStatuses(t *testing.T) {
	text := UptimeTemplate("statbus.example.org")
	for _, wanted := range []string{
		"https://statbus.example.org/monitor",
		"200  ok, warning or upgrading",
		"503  critical or unknown",
	} {
		if !strings.Contains(text, wanted) {
			t.Errorf("uptime template missing %q:\n%s", wanted, text)
		}
	}
}
