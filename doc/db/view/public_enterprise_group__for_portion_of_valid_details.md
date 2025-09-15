```sql
                             View "public.enterprise_group__for_portion_of_valid"
          Column          |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                       | integer                  |           |          |         | plain    | 
 valid_from               | date                     |           |          |         | plain    | 
 valid_to                 | date                     |           |          |         | plain    | 
 valid_until              | date                     |           |          |         | plain    | 
 short_name               | character varying(16)    |           |          |         | extended | 
 name                     | character varying(256)   |           |          |         | extended | 
 enterprise_group_type_id | integer                  |           |          |         | plain    | 
 contact_person           | text                     |           |          |         | extended | 
 edit_comment             | character varying(512)   |           |          |         | extended | 
 edit_by_user_id          | integer                  |           |          |         | plain    | 
 edit_at                  | timestamp with time zone |           |          |         | plain    | 
 unit_size_id             | integer                  |           |          |         | plain    | 
 data_source_id           | integer                  |           |          |         | plain    | 
 reorg_references         | text                     |           |          |         | extended | 
 reorg_date               | timestamp with time zone |           |          |         | plain    | 
 reorg_type_id            | integer                  |           |          |         | plain    | 
 foreign_participation_id | integer                  |           |          |         | plain    | 
View definition:
 SELECT id,
    valid_from,
    valid_to,
    valid_until,
    short_name,
    name,
    enterprise_group_type_id,
    contact_person,
    edit_comment,
    edit_by_user_id,
    edit_at,
    unit_size_id,
    data_source_id,
    reorg_references,
    reorg_date,
    reorg_type_id,
    foreign_participation_id
   FROM enterprise_group;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON enterprise_group__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
