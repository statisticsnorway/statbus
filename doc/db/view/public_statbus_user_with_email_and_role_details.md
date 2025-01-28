```sql
                        View "public.statbus_user_with_email_and_role"
  Column   |          Type          | Collation | Nullable | Default | Storage  | Description 
-----------+------------------------+-----------+----------+---------+----------+-------------
 email     | character varying(255) |           |          |         | extended | 
 role_type | statbus_role_type      |           |          |         | plain    | 
View definition:
 SELECT au.email,
    sr.type AS role_type
   FROM auth.users au
     JOIN statbus_user su ON au.id = su.uuid
     JOIN statbus_role sr ON su.role_id = sr.id;
Triggers:
    update_statbus_user_with_email_and_role INSTEAD OF UPDATE ON statbus_user_with_email_and_role FOR EACH ROW EXECUTE FUNCTION admin.trigger_update_statbus_user_with_email_and_role()
Options: security_barrier=true

```
