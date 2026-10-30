package monitor

import (
	"fmt"
	"strings"
)

// ZabbixTemplate returns a Zabbix 7 template (YAML export format) whose master
// item runs `sb monitor status --format json` through a UserParameter and whose
// dependent items and triggers read the JSON. The same UserParameter line
// appears in the header so an operator can copy it into the agent
// configuration before importing the template.
//
// The template is static; this site's domain never appears in it, so one file
// works for every StatBus box.
func ZabbixTemplate() string {
	return `# Zabbix 7 template for StatBus.
#
# On the StatBus host, add this line to the Zabbix agent configuration
# (usually /etc/zabbix/zabbix_agentd.conf) and restart the agent:
#
# UserParameter=statbus.monitor,/home/statbus/statbus/sb monitor status --format json
#
# Import this file with Data collection -> Templates -> Import.
# The master item runs the CLI; dependent items read the JSON with JSONPath.
zabbix_export:
  version: '7.0'
  template_groups:
    - uuid: 7a9e3a2c1b5d4c8e9f6a0b1c2d3e4f50
      name: 'Templates/Applications'
  templates:
    - uuid: 1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f
      template: StatBus
      name: StatBus
      description: |
        StatBus health. The master item runs:
          /home/statbus/statbus/sb monitor status --format json
        status is ok, warning, critical, unknown or upgrading.
        Exit codes: 0 ok, 1 warning/upgrading, 2 critical, 3 unknown.
      groups:
        - name: 'Templates/Applications'
      items:
        - uuid: 2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f70
          name: 'StatBus monitor JSON'
          type: ZABBIX_PASSIVE
          key: statbus.monitor
          delay: 1m
          history: 7d
          value_type: TEXT
          description: 'One health reading from ./sb monitor status --format json.'
          tags:
            - tag: component
              value: statbus
        - uuid: 3e4f5a6b7c8d9e0f1a2b3c4d5e6f7081
          name: 'StatBus status'
          type: DEPENDENT
          key: statbus.status
          history: 90d
          value_type: CHAR
          description: 'Overall StatBus status.'
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - '$.status'
          tags:
            - tag: component
              value: statbus
        - uuid: 4f5a6b7c8d9e0f1a2b3c4d5e6f708192
          name: 'StatBus checked at'
          type: DEPENDENT
          key: statbus.checked_at_unixtime
          history: 7d
          value_type: UNSIGNED
          units: unixtime
          description: 'When the reading was taken, in Unix time. A reading older than 5 minutes means the upgrader tick has stopped.'
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - '$.checked_at'
            - type: JAVASCRIPT
              parameters:
                - 'return Math.floor(new Date(value).getTime() / 1000);'
          tags:
            - tag: component
              value: statbus
        - uuid: 5a6b7c8d9e0f1a2b3c4d5e6f708192a3
          name: 'StatBus check: services'
          type: DEPENDENT
          key: statbus.check.services
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='services')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: 6b7c8d9e0f1a2b3c4d5e6f708192a3b4
          name: 'StatBus check: api'
          type: DEPENDENT
          key: statbus.check.api
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='api')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: 7c8d9e0f1a2b3c4d5e6f708192a3b4c5
          name: 'StatBus check: site'
          type: DEPENDENT
          key: statbus.check.site
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='site')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: 8d9e0f1a2b3c4d5e6f708192a3b4c5d6
          name: 'StatBus check: disk'
          type: DEPENDENT
          key: statbus.check.disk
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='disk')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: 9e0f1a2b3c4d5e6f708192a3b4c5d6e7
          name: 'StatBus check: backups'
          type: DEPENDENT
          key: statbus.check.backups
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='backups')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: a0f1a2b3c4d5e6f708192a3b4c5d6e7f8
          name: 'StatBus check: upgrader'
          type: DEPENDENT
          key: statbus.check.upgrader
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='upgrader')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
        - uuid: b1a2b3c4d5e6f708192a3b4c5d6e7f809
          name: 'StatBus check: worker'
          type: DEPENDENT
          key: statbus.check.worker
          history: 90d
          value_type: CHAR
          master_item:
            key: statbus.monitor
          preprocessing:
            - type: JSONPATH
              parameters:
                - "$.checks[?(@.name=='worker')].status"
            - type: JAVASCRIPT
              parameters:
                - "return JSON.parse(value)[0] || 'unknown';"
          tags:
            - tag: component
              value: statbus
      triggers:
        - uuid: c2b3c4d5e6f708192a3b4c5d6e7f8091
          expression: 'last(/StatBus/statbus.status)="warning"'
          name: 'StatBus status is warning'
          priority: WARNING
          description: 'A check reports warning: disk space, certificate expiry, worker task failures, an inactive upgrader or a failed upgrade.'
          tags:
            - tag: component
              value: statbus
        - uuid: d3c4d5e6f708192a3b4c5d6e7f8091a
          expression: 'last(/StatBus/statbus.status)="critical"'
          name: 'StatBus status is critical'
          priority: HIGH
          description: 'A check reports critical: a serving container is down, the API is not ready, the site does not answer, disk is below the minimum, backups stopped, an upgrade is parked or worker tasks are stuck.'
          tags:
            - tag: component
              value: statbus
        - uuid: e4d5e6f708192a3b4c5d6e7f8091a2b
          expression: 'last(/StatBus/statbus.status)="unknown"'
          name: 'StatBus status is unknown'
          priority: WARNING
          description: 'A check could not be measured. Inspect /monitor and ./sb monitor status on the StatBus host.'
          tags:
            - tag: component
              value: statbus
        - uuid: f5e6f708192a3b4c5d6e7f8091a2b3c
          expression: 'now() - last(/StatBus/statbus.checked_at_unixtime)>300'
          name: 'StatBus reading is stale'
          priority: WARNING
          description: 'The cached reading is older than 5 minutes: the upgrader tick that writes it has stopped.'
          tags:
            - tag: component
              value: statbus
`
}

// UptimeTemplate returns the HTTP-polling instructions for StatBus. Every
// consumer of the same public URL needs the same two facts: where to point and
// which HTTP statuses mean healthy.
func UptimeTemplate(domain string) string {
	url := "https://" + strings.TrimSpace(domain) + "/monitor"
	return fmt.Sprintf(`StatBus health URL for uptime monitors

URL:              %s
Method:           GET
Check interval:   1 minute (the upgrader refreshes the reading every 60 s)

Expected status:
  200  ok, warning or upgrading (a warning or a planned upgrade is not an outage)
  503  critical or unknown (a check failed or could not be measured)

Uptime Kuma:
  1. Add a new monitor, type "HTTP(s) - Keyword" or "HTTP(s)".
  2. URL: %s
  3. Expected status codes: 200
  4. (Optional, Keyword monitor) Keyword: "ok" or "warning", invert the match.

UptimeRobot:
  1. Add a new monitor, type "HTTP(s)".
  2. URL: %s
  3. Monitoring interval: 1 minute.
  4. Leave "Alert when status is not 200" enabled: 503 is the alert.

The JSON body also reports checked_at. Treat a checked_at older than 5 minutes
as stale: the upgrader tick that writes the reading has stopped, even though
the web server still answers 200.
`, url, url, url)
}
