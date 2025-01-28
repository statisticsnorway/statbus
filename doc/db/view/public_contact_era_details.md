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
 SELECT contact.id,
    contact.valid_after,
    contact.valid_from,
    contact.valid_to,
    contact.web_address,
    contact.email_address,
    contact.phone_number,
    contact.landline,
    contact.mobile_number,
    contact.fax_number,
    contact.establishment_id,
    contact.legal_unit_id,
    contact.data_source_id,
    contact.edit_comment,
    contact.edit_by_user_id,
    contact.edit_at
   FROM contact;
Triggers:
    contact_era_upsert INSTEAD OF INSERT ON contact_era FOR EACH ROW EXECUTE FUNCTION admin.contact_era_upsert()
Options: security_invoker=on

```
