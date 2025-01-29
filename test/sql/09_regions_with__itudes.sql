BEGIN;

\echo "Testing regions with coordinates"

-- Test invalid latitude (>90)
SAVEPOINT bad_latitude;
\echo "Testing invalid latitude value"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
91,Invalid,91.0,10.0,10
\.
ROLLBACK TO bad_latitude;

-- Test invalid longitude (>180)
SAVEPOINT bad_longitude;
\echo "Testing invalid longitude value"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
92,Invalid,60.0,181.0,10
\.
ROLLBACK TO bad_longitude;

-- Test negative altitude
SAVEPOINT negative_altitude;
\echo "Testing negative altitude value"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
93,Invalid,60.0,10.0,-1
\.
ROLLBACK TO negative_altitude;

-- Test invalid coordinate syntax
SAVEPOINT bad_syntax;
\echo "Testing invalid coordinate syntax"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
94,Invalid,60.0.1,10.0,10
\.
ROLLBACK TO bad_syntax;

-- Test invalid path syntax
SAVEPOINT bad_path;
\echo "Testing invalid path syntax"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
01:1,Invalid,60.0,10.0,10
\.
ROLLBACK TO bad_path;

\echo "Loading regions with latitude, longitude and altitude"
\copy public.region_upload(path,name,center_latitude,center_longitude,center_altitude) FROM stdin WITH (FORMAT csv, DELIMITER ',');
03,Oslo,59.913868,10.752245,23
11,Rogaland,58.969975,5.733107,50
15,Møre og Romsdal,62.846827,7.161711,100
18,Nordland - Nordlánnda,67.280416,14.404916,150
\.

\echo "Verifying loaded regions with coordinates"
SELECT path
     , name
     , center_latitude
     , center_longitude
     , center_altitude
  FROM public.region
 WHERE center_latitude IS NOT NULL
 ORDER BY path;

ROLLBACK;
