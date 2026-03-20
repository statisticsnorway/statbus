```sql
                       View "public.tag_custom"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 path        | ltree                  |           |          | 
 name        | character varying(256) |           |          | 
 description | text                   |           |          | 
Triggers:
    prepare_tag_custom BEFORE INSERT ON tag_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_tag_custom()
    upsert_tag_custom INSTEAD OF INSERT ON tag_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_tag_custom()

```
