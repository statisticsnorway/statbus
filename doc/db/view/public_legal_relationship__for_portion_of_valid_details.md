```sql
                               View "public.legal_relationship__for_portion_of_valid"
             Column             |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                             | integer                  |           |          |         | plain    | 
 derived_power_group_id         | integer                  |           |          |         | plain    | 
 derived_influenced_power_level | integer                  |           |          |         | plain    | 
 valid_range                    | daterange                |           |          |         | extended | 
 valid_from                     | date                     |           |          |         | plain    | 
 valid_to                       | date                     |           |          |         | plain    | 
 valid_until                    | date                     |           |          |         | plain    | 
 influencing_id                 | integer                  |           |          |         | plain    | 
 influenced_id                  | integer                  |           |          |         | plain    | 
 type_id                        | integer                  |           |          |         | plain    | 
 reorg_type_id                  | integer                  |           |          |         | plain    | 
 primary_influencer_only        | boolean                  |           |          |         | plain    | 
 percentage                     | numeric(5,2)             |           |          |         | main     | 
 edit_comment                   | character varying(512)   |           |          |         | extended | 
 edit_by_user_id                | integer                  |           |          |         | plain    | 
 edit_at                        | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    derived_power_group_id,
    derived_influenced_power_level,
    valid_range,
    valid_from,
    valid_to,
    valid_until,
    influencing_id,
    influenced_id,
    type_id,
    reorg_type_id,
    primary_influencer_only,
    percentage,
    edit_comment,
    edit_by_user_id,
    edit_at
   FROM legal_relationship;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON legal_relationship__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')
Options: security_invoker=on

```
