# Plan
The import system needs to use our new import_job system.
You can see it in action in test/sql/50_import_jobs_for_norway_small_history.sql

The relevant import definitions are
```
statbus_dev=# select slug,name from import_definition;
                  slug                   |                       name
-----------------------------------------+---------------------------------------------------
 establishment_without_lu_explicit_dates | Establishment without Legal Unit - Explicit Dates
 establishment_without_lu_current_year   | Establishment without Legal Unit - Current Year
 establishment_for_lu_explicit_dates     | Establishment for Legal Unit - Explicit Dates
 establishment_for_lu_current_year       | Establishment for Legal Unit - Current Year
 legal_unit_explicit_dates               | Legal Unit - Explicit Dates
 legal_unit_current_year                 | Legal Unit - Current Year
 (6 rows)
 ```
 
 The flow will be a little different.
 When the user selects "Upload Legal Units" from the menu, the current time context is fetched and it reads
 ```
   Upload Legal Units
   (*) for $selected_time_context
   ( ) with valid_from and valid_to columns
   [Continue][Skip]
 ```
the continue button creates the import_job (like in the test) and depdening on the selection, sets the default valid_from and valid_to for the new import_job.

After pressing `[Continue]` the screen changes to
 ```
   Upload Legal Units [for $selected_time_context|with valid_from and valid_to columns]
   [Select file]
   [Upload][Cancel]
 ```

Where Upload will POST the file to /api/import with import_job_slug and the POST handler
will connect to the datase DIRECTLY (not throught /rest) and INSERT into the import_job.upload_table_name
table in the most efficient way possible using https://github.com/brianc/node-pg-copy-streams

The upload is relatively fast, but there should be two progress bars,
```
    sending to server [>>>.....]
    copying from server to holding table [>>>.....]
```

After that the import_job table will have the information required to see the state of the job.

The import_job system needs to post a NOTIFY every time there is a state change,
this should use the existing before_/after_procedure of a command.
The procedure must take a parameter that contains the relevant import_job_slug,
however we don't wan't to send updates for every job to every client,
however on the backend the body can be `import_job_$slug`,
and then the app only sends those notifications to the slug's the client
connect for.

Create a new page /import/jobs "Import Jobs" and put it in the Command Palette.
On this page load the import_jobs table with relevant information for the user,
along with registering for updates to keep it up to date.

Before we used `api/sse/worker-check` for the SSE endpoint,
but now you made `api/sse/import-job/[id]`, think we should have `api/sse/worker/check` and `api/sse/import/check`
that takes an `import_job_ids` argument, so that only one sse is used even if multiple import_jobs are displayed
and live updated.
