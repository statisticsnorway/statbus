```sql
                 View "public.person_for_unit__for_portion_of_valid"
      Column      |  Type   | Collation | Nullable | Default | Storage | Description 
------------------+---------+-----------+----------+---------+---------+-------------
 id               | integer |           |          |         | plain   | 
 valid_from       | date    |           |          |         | plain   | 
 valid_to         | date    |           |          |         | plain   | 
 valid_until      | date    |           |          |         | plain   | 
 person_id        | integer |           |          |         | plain   | 
 person_role_id   | integer |           |          |         | plain   | 
 data_source_id   | integer |           |          |         | plain   | 
 establishment_id | integer |           |          |         | plain   | 
 legal_unit_id    | integer |           |          |         | plain   | 
View definition:
 SELECT id,
    valid_from,
    valid_to,
    valid_until,
    person_id,
    person_role_id,
    data_source_id,
    establishment_id,
    legal_unit_id
   FROM person_for_unit;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON person_for_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
