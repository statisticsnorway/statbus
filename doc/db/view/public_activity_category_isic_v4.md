```sql
                View "public.activity_category_isic_v4"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 standard    | character varying(16)  |           |          | 
 path        | ltree                  |           |          | 
 label       | character varying      |           |          | 
 code        | character varying      |           |          | 
 name        | character varying(256) |           |          | 
 description | text                   |           |          | 
Triggers:
    delete_stale_activity_category_isic_v4 AFTER INSERT ON activity_category_isic_v4 FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_activity_category()
    upsert_activity_category_isic_v4 INSTEAD OF INSERT ON activity_category_isic_v4 FOR EACH ROW EXECUTE FUNCTION admin.upsert_activity_category('isic_v4')

```
