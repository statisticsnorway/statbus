```sql
                           View "public.activity_era"
       Column       |           Type           | Collation | Nullable | Default 
--------------------+--------------------------+-----------+----------+---------
 id                 | integer                  |           |          | 
 valid_after        | date                     |           |          | 
 valid_from         | date                     |           |          | 
 valid_to           | date                     |           |          | 
 type               | activity_type            |           |          | 
 category_id        | integer                  |           |          | 
 data_source_id     | integer                  |           |          | 
 updated_by_user_id | integer                  |           |          | 
 updated_at         | timestamp with time zone |           |          | 
 establishment_id   | integer                  |           |          | 
 legal_unit_id      | integer                  |           |          | 
Triggers:
    activity_era_upsert INSTEAD OF INSERT ON activity_era FOR EACH ROW EXECUTE FUNCTION admin.activity_era_upsert()

```
