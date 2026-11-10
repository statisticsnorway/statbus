```sql
                                                                                                          View "public.time_frame"
       Column       |      Type       | Collation | Nullable | Default | Storage  |                                                                       Description                                                                        
--------------------+-----------------+-----------+----------+---------+----------+----------------------------------------------------------------------------------------------------------------------------------------------------------
 ident              | text            |           |          |         | extended | The stable name of the frame: live, prev, or y_YYYY. Import jobs and saved selections refer to it; live and prev keep their ident as the calendar moves.
 kind               | time_frame_kind |           |          |         | plain    | live, relative or fixed (public.time_frame_kind).
 name               | text            |           |          |         | extended | The name shown to users: Live frame (YYYY), Previous frame (YYYY) or Frame YYYY.
 valid_from         | date            |           |          |         | plain    | First day of the frame.
 valid_to           | date            |           |          |         | plain    | Last day of the frame, inclusive; infinity for the live frame.
 valid_on           | date            |           |          |         | plain    | The day the frame is read as of: today for the live frame, 31 December for a closed year.
 year               | integer         |           |          |         | plain    | The calendar year the frame starts in.
 equals_frame_ident | text            |           |          |         | extended | For a fixed frame, the relative frame covering the same year today (prev for the previous year), else NULL.
View definition:
 WITH today AS (
         SELECT COALESCE(NULLIF(current_setting('app.current_date'::text, true), ''::text)::date, CURRENT_DATE) AS date
        ), years AS (
         SELECT EXTRACT(year FROM today.date)::integer AS current_year
           FROM today
        ), frames AS (
         SELECT 'live'::text AS ident,
            'live'::time_frame_kind AS kind,
            format('Live frame (%s)'::text, y.current_year) AS name,
            make_date(y.current_year, 1, 1) AS valid_from,
            'infinity'::date AS valid_to,
            today.date AS valid_on,
            y.current_year AS year,
            NULL::text AS equals_frame_ident
           FROM years y
             CROSS JOIN today
        UNION ALL
         SELECT 'prev'::text,
            'relative'::time_frame_kind,
            format('Previous frame (%s)'::text, y.current_year - 1) AS format,
            make_date(y.current_year - 1, 1, 1) AS make_date,
            make_date(y.current_year - 1, 12, 31) AS make_date,
            make_date(y.current_year - 1, 12, 31) AS make_date,
            y.current_year - 1,
            NULL::text
           FROM years y
        UNION ALL
         SELECT 'y_'::text || fy.year,
            'fixed'::time_frame_kind,
            format('Frame %s'::text, fy.year) AS format,
            make_date(fy.year, 1, 1) AS make_date,
            make_date(fy.year, 12, 31) AS make_date,
            make_date(fy.year, 12, 31) AS make_date,
            fy.year,
                CASE
                    WHEN fy.year = (y.current_year - 1) THEN 'prev'::text
                    ELSE NULL::text
                END AS "case"
           FROM years y
             CROSS JOIN LATERAL ( SELECT ty.year
                   FROM timesegments_years ty
                  WHERE ty.year < y.current_year
                UNION
                 SELECT y.current_year - 1) fy
        )
 SELECT ident,
    kind,
    name,
    valid_from,
    valid_to,
    valid_on,
    year,
    equals_frame_ident
   FROM frames
  ORDER BY kind, valid_from DESC;
Options: security_invoker=on

```

**Comment:** The time frames a user looks at the timelines through, for the current date (app.current_date, else CURRENT_DATE): the live frame (ident live), the relative frame for the previous year (ident prev) and a fixed frame per closed year (ident y_YYYY) for the previous year and every earlier year with data. Ordered live, relative, fixed, newest first; the first row is the default. The frame menu leaves out a fixed frame whose equals_frame_ident is set, because it shows the same years as that relative frame today; import pages show every frame.
