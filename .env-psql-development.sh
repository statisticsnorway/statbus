WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export PGHOST=localhost
export PGPORT=$(awk -F '=' '/POSTGRES_PORT/{print $2}' $WORKSPACE/supabase/docker/.env)
export PGUSER=postgres
export PGDATABASE=$(awk -F '=' '/POSTGRES_DB/{print $2}' $WORKSPACE/supabase/docker/.env)
export PGPASSWORD=$(awk -F '=' '/POSTGRES_PASSWORD/{print $2}' $WORKSPACE/supabase/docker/.env)