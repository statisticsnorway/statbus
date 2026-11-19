```sql
                                       Table "admin.image_released"
  Column  |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
----------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 image_id | integer |           | not null |         | plain   |             |              | 
Not-null constraints:
    "image_released_image_id_not_null" NOT NULL "image_id"
Triggers:
    image_released_check AFTER INSERT ON admin.image_released DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION image_drop_released()
Access method: heap

```

**Comment:** Photos a legal_unit or establishment row stopped referring to in the current transaction, noted by public.image_note_released. A deferred trigger on this table (public.image_drop_released) deletes each at commit when no row refers to it any more, and removes the note; the table is empty outside a transaction. The deferred work sits here rather than on legal_unit and establishment because deferred events pending on those tables would make ALTER TABLE on them fail inside the transaction, and imports enable and disable sql_saga's triggers between batches. No grants: only the SECURITY DEFINER trigger functions use it.
