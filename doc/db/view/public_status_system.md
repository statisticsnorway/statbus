```sql
                                    View "public.status_system"
       Column        |       Type        | Collation | Nullable | Default | Storage  | Description 
---------------------+-------------------+-----------+----------+---------+----------+-------------
 code                | character varying |           |          |         | extended | 
 name                | text              |           |          |         | extended | 
 priority            | integer           |           |          |         | plain    | 
 assigned_by_default | boolean           |           |          |         | plain    | 
 used_for_counting   | boolean           |           |          |         | plain    | 
View definition:
 SELECT code,
    name,
    priority,
    assigned_by_default,
    used_for_counting
   FROM status_enabled
  WHERE custom = false;
Triggers:
    upsert_status_system INSTEAD OF INSERT ON status_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_system()
Options: security_invoker=on

```
