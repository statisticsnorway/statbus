```sql
            View "public.activity_category_enabled_custom"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 path        | ltree                  |           |          | 
 name        | character varying(256) |           |          | 
 description | text                   |           |          | 
Triggers:
    activity_category_enabled_custom_upsert_custom INSTEAD OF INSERT ON activity_category_enabled_custom FOR EACH ROW EXECUTE FUNCTION admin.activity_category_enabled_custom_upsert_custom()

```
