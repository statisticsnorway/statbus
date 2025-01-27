```sql
                                      View "public.activity_era"
      Column      |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------+--------------------------+-----------+----------+---------+----------+-------------
 id               | integer                  |           |          |         | plain    | 
 valid_after      | date                     |           |          |         | plain    | 
 valid_from       | date                     |           |          |         | plain    | 
 valid_to         | date                     |           |          |         | plain    | 
 type             | activity_type            |           |          |         | plain    | 
 category_id      | integer                  |           |          |         | plain    | 
 data_source_id   | integer                  |           |          |         | plain    | 
 edit_comment     | character varying(512)   |           |          |         | extended | 
 edit_by_user_id  | integer                  |           |          |         | plain    | 
 edit_at          | timestamp with time zone |           |          |         | plain    | 
 establishment_id | integer                  |           |          |         | plain    | 
 legal_unit_id    | integer                  |           |          |         | plain    | 
View definition:
 SELECT activity.id,
    activity.valid_after,
    activity.valid_from,
    activity.valid_to,
    activity.type,
    activity.category_id,
    activity.data_source_id,
    activity.edit_comment,
    activity.edit_by_user_id,
    activity.edit_at,
    activity.establishment_id,
    activity.legal_unit_id
   FROM activity;
Triggers:
    activity_era_upsert INSTEAD OF INSERT ON activity_era FOR EACH ROW EXECUTE FUNCTION admin.activity_era_upsert()
Options: security_invoker=on

```
