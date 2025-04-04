```sql
                                       View "public.contact_era"
      Column      |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------+--------------------------+-----------+----------+---------+----------+-------------
 id               | integer                  |           |          |         | plain    | 
 valid_after      | date                     |           |          |         | plain    | 
 valid_from       | date                     |           |          |         | plain    | 
 valid_to         | date                     |           |          |         | plain    | 
 web_address      | character varying(256)   |           |          |         | extended | 
 email_address    | character varying(50)    |           |          |         | extended | 
 phone_number     | character varying(50)    |           |          |         | extended | 
 landline         | character varying(50)    |           |          |         | extended | 
 mobile_number    | character varying(50)    |           |          |         | extended | 
 fax_number       | character varying(50)    |           |          |         | extended | 
 establishment_id | integer                  |           |          |         | plain    | 
 legal_unit_id    | integer                  |           |          |         | plain    | 
 data_source_id   | integer                  |           |          |         | plain    | 
 edit_comment     | character varying(512)   |           |          |         | extended | 
 edit_by_user_id  | integer                  |           |          |         | plain    | 
 edit_at          | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    valid_after,
    valid_from,
    valid_to,
    web_address,
    email_address,
    phone_number,
    landline,
    mobile_number,
    fax_number,
    establishment_id,
    legal_unit_id,
    data_source_id,
    edit_comment,
    edit_by_user_id,
    edit_at
   FROM contact;
Triggers:
    contact_era_upsert INSTEAD OF INSERT ON contact_era FOR EACH ROW EXECUTE FUNCTION admin.contact_era_upsert()
Options: security_invoker=on

```
