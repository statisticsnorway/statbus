```sql
                      View "public.hypopg_hidden_indexes"
   Column    |  Type   | Collation | Nullable | Default | Storage | Description 
-------------+---------+-----------+----------+---------+---------+-------------
 indexrelid  | oid     |           |          |         | plain   | 
 index_name  | name    |           |          |         | plain   | 
 schema_name | name    |           |          |         | plain   | 
 table_name  | name    |           |          |         | plain   | 
 am_name     | name    |           |          |         | plain   | 
 is_hypo     | boolean |           |          |         | plain   | 
View definition:
 SELECT h.indexid AS indexrelid,
    i.relname AS index_name,
    n.nspname AS schema_name,
    t.relname AS table_name,
    m.amname AS am_name,
    false AS is_hypo
   FROM hypopg_hidden_indexes() h(indexid)
     JOIN pg_index x ON x.indexrelid = h.indexid
     JOIN pg_class i ON i.oid = h.indexid
     JOIN pg_namespace n ON n.oid = i.relnamespace
     JOIN pg_class t ON t.oid = x.indrelid
     JOIN pg_am m ON m.oid = i.relam
UNION ALL
 SELECT hl.indexrelid,
    hl.index_name,
    hl.schema_name,
    hl.table_name,
    hl.am_name,
    true AS is_hypo
   FROM hypopg_hidden_indexes() hi(indexid)
     JOIN hypopg_list_indexes hl ON hl.indexrelid = hi.indexid
  ORDER BY 2;

```
