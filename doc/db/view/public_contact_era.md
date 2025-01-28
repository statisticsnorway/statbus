```sql
                          View "public.contact_era"
      Column      |           Type           | Collation | Nullable | Default 
------------------+--------------------------+-----------+----------+---------
 id               | integer                  |           |          | 
 valid_after      | date                     |           |          | 
 valid_from       | date                     |           |          | 
 valid_to         | date                     |           |          | 
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
    contact_era_upsert INSTEAD OF INSERT ON contact_era FOR EACH ROW EXECUTE FUNCTION admin.contact_era_upsert()

```
