WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export PGHOST=localhost
#export PGPORT=$(awk -F '=' '/POSTGRES_PORT/{print $2}' $WORKSPACE/.env)
export PGPORT=3432
export PGUSER=postgres
export PGDATABASE=$(awk -F '=' '/POSTGRES_DB/{print $2}' $WORKSPACE/.env)
export PGPASSWORD=$(awk -F '=' '/POSTGRES_PASSWORD/{print $2}' $WORKSPACE/.env)
