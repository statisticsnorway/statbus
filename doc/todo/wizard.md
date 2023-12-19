# Wizard Steps

# Log in

Go to https://www.dev.statbus.org/ and log in.

Inspect the network traffic/cookies and find the authKey.
Replace below and run the exports.
```
export apiKey="..."
export apiKeyHeader="apikey: $apiKey"
export authKey="..."
export authKeyHeader="Authorization: Bearer $authKey"
```
# Check if there are any settings
curl 'https://api.dev.statbus.org/rest/v1/settings?select=*,activity_category_standard(id,name)' \
-H $apiKeyHeader -H $authKeyHeader

# If empty, then list the available category standards
curl 'https://api.dev.statbus.org/rest/v1/activity_category_standard' \
-H $apiKeyHeader -H $authKeyHeader

# Insert a setting with the chosen category standard

curl -X POST 'https://api.dev.statbus.org/rest/v1/settings?select=*,activity_category_standard(id,name)' \
-H $apiKeyHeader -H $authKeyHeader \
-H "Content-Type: application/json" \
-H "Prefer: return=representation" \
-d '{ "activity_category_standard_id": "2", "only_one_setting":true}'

# Or update an existing setting
curl -X PATCH 'https://api.dev.statbus.org/rest/v1/settings?select=*,activity_category_standard(id,name)&only_one_setting=eq.true' \
-H $apiKeyHeader -H $authKeyHeader \
-H "Content-Type: application/json" \
-H "Prefer: return=representation" \
-d '{ "activity_category_standard_id": "2"}'


# Look at available activity_categories

curl 'https://api.dev.statbus.org/rest/v1/activity_category?select=path,name&order=path' \
-H $apiKeyHeader -H $authKeyHeader

# Look at available regions

curl 'https://api.dev.statbus.org/rest/v1/region?select=path,name&order=path' \
-H $apiKeyHeader -H $authKeyHeader

# Upload new regions

curl -X POST 'https://api.dev.statbus.org/rest/v1/region' \
-H $apiKeyHeader -H $authKeyHeader \
-H "Content-Type: text/csv" \
--data-binary '@samples/norway-sample-regions.csv'

# Verify new regions
curl 'https://api.dev.statbus.org/rest/v1/region?select=path,name&order=path' \
-H $apiKeyHeader -H $authKeyHeader


# Generate ER diagram for display with https://mermaid.js.org/
curl 'https://api.dev.statbus.org/rest/v1/rpc/generate_mermaid_er_diagram' \
-H $apiKeyHeader -H $authKeyHeader


