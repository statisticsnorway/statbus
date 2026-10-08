```sql
                                    View "public.status_custom"
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
  WHERE custom = true;
Triggers:
    prepare_status_custom BEFORE INSERT ON status_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_status_custom()
    upsert_status_custom INSTEAD OF INSERT ON status_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_status_custom()
Options: security_invoker=on

```
