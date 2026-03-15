```sql
                                    View "public.tag_custom"
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
  WHERE custom = true;
Triggers:
    prepare_tag_custom BEFORE INSERT ON tag_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_tag_custom()
    upsert_tag_custom INSTEAD OF INSERT ON tag_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_tag_custom()
Options: security_invoker=on

```
