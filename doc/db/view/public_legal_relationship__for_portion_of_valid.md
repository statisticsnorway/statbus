```sql
                   View "public.legal_relationship__for_portion_of_valid"
             Column             |           Type           | Collation | Nullable | Default 
--------------------------------+--------------------------+-----------+----------+---------
 id                             | integer                  |           |          | 
 derived_power_group_id         | integer                  |           |          | 
 derived_influenced_power_level | integer                  |           |          | 
 valid_range                    | daterange                |           |          | 
 valid_from                     | date                     |           |          | 
 valid_to                       | date                     |           |          | 
 valid_until                    | date                     |           |          | 
 influencing_id                 | integer                  |           |          | 
 influenced_id                  | integer                  |           |          | 
 type_id                        | integer                  |           |          | 
 reorg_type_id                  | integer                  |           |          | 
 primary_influencer_only        | boolean                  |           |          | 
 percentage                     | numeric(5,2)             |           |          | 
 edit_comment                   | character varying(512)   |           |          | 
 edit_by_user_id                | integer                  |           |          | 
 edit_at                        | timestamp with time zone |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON legal_relationship__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
