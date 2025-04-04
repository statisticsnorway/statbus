```sql
                      View "public.hypopg_list_indexes"
   Column    | Type | Collation | Nullable | Default | Storage  | Description 
-------------+------+-----------+----------+---------+----------+-------------
 indexrelid  | oid  |           |          |         | plain    | 
 index_name  | text |           |          |         | extended | 
 schema_name | name |           |          |         | plain    | 
 table_name  | name |           |          |         | plain    | 
 am_name     | name |           |          |         | plain    | 
View definition:
 SELECT h.indexrelid,
    h.indexname AS index_name,
    n.nspname AS schema_name,
    COALESCE(c.relname, '<dropped>'::name) AS table_name,
    am.amname AS am_name
   FROM hypopg() h(indexname, indexrelid, indrelid, innatts, indisunique, indkey, indcollation, indclass, indoption, indexprs, indpred, amid)
     LEFT JOIN pg_class c ON c.oid = h.indrelid
     LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
     LEFT JOIN pg_am am ON am.oid = h.amid;

```
