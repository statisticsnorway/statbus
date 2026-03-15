```sql
                                    View "public.tag_system"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------
 path        | ltree                  |           |          |         | extended | 
 name        | character varying(256) |           |          |         | extended | 
 description | text                   |           |          |         | extended | 
View definition:
 SELECT path,
    name,
    description
   FROM tag_enabled
  WHERE custom = false;
Triggers:
    upsert_tag_system INSTEAD OF INSERT ON tag_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_tag_system()
Options: security_invoker=on

```
