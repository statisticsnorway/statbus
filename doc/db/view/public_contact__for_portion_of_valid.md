```sql
                 View "public.contact__for_portion_of_valid"
      Column      |           Type           | Collation | Nullable | Default 
------------------+--------------------------+-----------+----------+---------
 id               | integer                  |           |          | 
 valid_range      | daterange                |           |          | 
 valid_from       | date                     |           |          | 
 valid_to         | date                     |           |          | 
 valid_until      | date                     |           |          | 
 web_address      | character varying(256)   |           |          | 
 email_address    | character varying(50)    |           |          | 
 phone_number     | character varying(50)    |           |          | 
 landline         | character varying(50)    |           |          | 
 mobile_number    | character varying(50)    |           |          | 
 fax_number       | character varying(50)    |           |          | 
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           |          | 
 edit_at          | timestamp with time zone |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON contact__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
