# Testing Rules

## Never run destructive database commands without asking

Always ask the user before running commands that destroy or recreate the development database:
- `./devops/manage-statbus.sh recreate-database`
- `./devops/manage-statbus.sh delete-db`
- `./devops/manage-statbus.sh delete-db-structure`
- `./devops/manage-statbus.sh create-db` (drops and recreates)

Tests (`./devops/manage-statbus.sh test`) are safe — they run against cloned databases, not the user's active development database.
