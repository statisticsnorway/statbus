```sql
                                             Table "auth.schema_migrations"
 Column  |          Type          | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
---------+------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 version | character varying(255) |           | not null |         | extended |             |              | 
Indexes:
    "schema_migrations_pkey" PRIMARY KEY, btree (version)
Policies (row security enabled): (none)
Access method: heap

```
