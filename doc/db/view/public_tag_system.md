```sql
                       View "public.tag_system"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 path        | ltree                  |           |          | 
 name        | character varying(256) |           |          | 
 description | text                   |           |          | 
Triggers:
    upsert_tag_system INSTEAD OF INSERT ON tag_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_tag_system()

```
