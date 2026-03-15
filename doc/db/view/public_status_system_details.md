```sql
                              View "public.status_system"
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
  WHERE custom = false;
Triggers:
    upsert_status_system INSTEAD OF INSERT ON status_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_system()
Options: security_invoker=on

```
