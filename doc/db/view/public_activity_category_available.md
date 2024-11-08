```sql
                View "public.activity_category_available"
    Column     |          Type          | Collation | Nullable | Default 
---------------+------------------------+-----------+----------+---------
 standard_code | character varying(16)  |           |          | 
 id            | integer                |           |          | 
 path          | ltree                  |           |          | 
 parent_path   | ltree                  |           |          | 
 code          | character varying      |           |          | 
 label         | character varying      |           |          | 
 name          | character varying(256) |           |          | 
 description   | text                   |           |          | 
 custom        | boolean                |           |          | 
Triggers:
    activity_category_available_upsert_custom INSTEAD OF INSERT ON activity_category_available FOR EACH ROW EXECUTE FUNCTION admin.activity_category_available_upsert_custom()

```
