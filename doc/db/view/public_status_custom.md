```sql
                              View "public.status_custom"
  Column  |       Type        | Collation | Nullable | Default | Storage  | Description 
----------+-------------------+-----------+----------+---------+----------+-------------
 code     | character varying |           |          |         | extended | 
 name     | text              |           |          |         | extended | 
 priority | integer           |           |          |         | plain    | 
View definition:
 SELECT code,
    name,
    priority
   FROM status_enabled
  WHERE custom = true;
Triggers:
    prepare_status_custom BEFORE INSERT ON status_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_status_custom()
    upsert_status_custom INSTEAD OF INSERT ON status_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_custom()
Options: security_invoker=on

```
