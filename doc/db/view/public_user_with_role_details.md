```sql
                             View "public.user"
    Column    |     Type     | Collation | Nullable | Default | Storage  | Description 
--------------+--------------+-----------+----------+---------+----------+-------------
 id           | integer      |           |          |         | plain    | 
 email        | text         |           |          |         | extended | 
 statbus_role | statbus_role |           |          |         | plain    | 
View definition:
 SELECT id,
    email,
    statbus_role
   FROM auth."user" u;
Triggers:
    update_user_with_role INSTEAD OF UPDATE ON user_with_role FOR EACH ROW EXECUTE FUNCTION admin.trigger_update_user_with_role()
Options: security_barrier=true

```
