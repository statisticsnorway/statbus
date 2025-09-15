```sql
     View "public.person_for_unit__for_portion_of_valid"
      Column      |  Type   | Collation | Nullable | Default 
------------------+---------+-----------+----------+---------
 id               | integer |           |          | 
 valid_from       | date    |           |          | 
 valid_to         | date    |           |          | 
 valid_until      | date    |           |          | 
 person_id        | integer |           |          | 
 person_role_id   | integer |           |          | 
 data_source_id   | integer |           |          | 
 establishment_id | integer |           |          | 
 legal_unit_id    | integer |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON person_for_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
