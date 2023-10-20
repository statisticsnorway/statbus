using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class PostgreSqlDbInitializer : IDbInitializer
    {
        [System.Obsolete]
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            #region Scripts

            const string dropStatUnitSearchView =
                """
                DROP VIEW IF EXISTS "V_StatUnitSearch";
                """;

            const string createStatUnitSearchView =
                """
                CREATE VIEW "V_StatUnitSearch"
                AS
                SELECT
                    "RegId",
                    "Name",
                    "ShortName",
                    "TaxRegId",
                    "StatId",
                    "ExternalId",
                    "act_addr"."Region_id" AS "ActualAddressRegionId",
                    "Employees",
                    "Turnover",
                    "InstSectorCodeId" AS "SectorCodeId",
                    "LegalFormId",
                    "DataSourceClassificationId",
                    "ChangeReason",
                    "StartPeriod",
                    "IsDeleted",
                    "LiqReason",
                    "LiqDate",
                    "act_addr"."Address_id" AS "ActualAddressId",
                    "act_addr"."Address_part1" AS "ActualAddressPart1",
                    "act_addr"."Address_part2" AS "ActualAddressPart2",
                    "act_addr"."Address_part3" AS "ActualAddressPart3",
                     CASE
                         WHEN "Discriminator" = 'LocalUnit' THEN 1
                         WHEN "Discriminator" = 'LegalUnit' THEN 2
                         WHEN "Discriminator" = 'EnterpriseUnit' THEN 3
                    END AS "UnitType"
                FROM "StatisticalUnits"
                LEFT JOIN "Address" as "act_addr" ON "ActualAddressId" = "act_addr"."Address_id"

                UNION ALL

                SELECT
                    "RegId",
                    "Name",
                    "ShortName",
                    "TaxRegId",
                    "StatId",
                    "ExternalId",
                    "act_addr"."Region_id" AS "ActualAddressRegionId",
                    "Employees",
                    "Turnover",
                    NULL AS "SectorCodeId",
                    NULL AS "LegalFormId",
                    "DataSourceClassificationId",
                    "ChangeReason",
                    "StartPeriod",
                    "IsDeleted",
                    "LiqReason",
                    "LiqDateEnd",
                    "act_addr"."Address_id" AS "ActualAddressId",
                    "act_addr"."Address_part1" AS "ActualAddressPart1",
                    "act_addr"."Address_part2" AS "ActualAddressPart2",
                    "act_addr"."Address_part3" AS "ActualAddressPart3",
                    4 AS "UnitType"
                FROM "EnterpriseGroups"
                LEFT JOIN "Address" as "act_addr" ON "ActualAddressId" = "act_addr"."Address_id"
                """;


            const string dropProcedureGetReportsTree =
                """
                DROP FUNCTION IF EXISTS GetReportsTree;
                """;

            /*
             * This query is for MS Sql to Query the SqlWallet sqlite 3 file - SQLWallet/sqlwallet.s3db
             * as configured in reportingSettings?.SQLiteConnectionString
             * Since SqlWallet is being removed from the project, this code is left as a query
             * from the non existing table "ReportTreeNode".
             * To activate this again, the PostgreSQL support for quering SQLite can be used
             * https://github.com/pgspider/sqlite_fdw or C# can directly open and query the
             * SQLite table, there is no need to funnel this through MS SQL/PostgreSQL,
             * when the file is directly available.
             */
            string createProcedureGetReportsTree =
                $"""
                 CREATE OR REPLACE FUNCTION GetReportsTree(p_user VARCHAR(100))
                 RETURNS TABLE
                 (
                     Id INT,
                     Title VARCHAR(500),
                     Type VARCHAR(100),
                     ReportId INT,
                     ParentNodeId INT,
                     IsDeleted BOOLEAN,
                     ResourceGroup VARCHAR(100),
                     ReportUrl VARCHAR
                 )
                 LANGUAGE 'plpgsql'
                 AS $BODY$
                 DECLARE
                     query TEXT;
                 BEGIN
                     query := 'SELECT
                                     Id,
                                     Title,
                                     Type,
                                     ReportId,
                                     ParentNodeId,
                                     IsDeleted,
                                     ResourceGroup,
                                     NULL as ReportUrl
                                FROM "ReportTreeNode" rtn
                                WHERE rtn.IsDeleted = FALSE
                                  AND (rtn.ReportId IS NULL OR rtn.ReportId IN (SELECT DISTINCT ReportId FROM ReportAce WHERE Principal = ''' || p_user || '''))';

                     RETURN QUERY EXECUTE query;
                 END;
                 $BODY$;
                 """;


            const string dropFunctionGetActivityChildren =
                """
                DROP FUNCTION IF EXISTS public."GetActivityChildren"(activityid integer,activitiesids varchar(400));
                """;

            const string createFunctionGetActivityChildren =
                """
                CREATE OR REPLACE FUNCTION public."GetActivityChildren"(activityid integer,activitiesids varchar(400))
                RETURNS TABLE("Id" integer, "Code" character varying, "DicParentId" integer, "IsDeleted" boolean, "Name" text, "NameLanguage1" text, "NameLanguage2" text, "ParentId" integer, "Section" character varying, "VersionId" integer, "ActivityCategoryLevel" integer)
                LANGUAGE 'plpgsql'
                AS $BODY$
                BEGIN
                    RETURN QUERY(
                    WITH RECURSIVE "ActivityCte" AS
                    (
                        SELECT
                          ac."Id"
                        , ac."Code"
                        , ac."DicParentId"
                        , ac."IsDeleted"
                        , ac."Name"
                        , ac."NameLanguage1"
                        , ac."NameLanguage2"
                        , ac."ParentId"
                        , ac."Section"
                        , ac."VersionId"
                        , ac."ActivityCategoryLevel"
                        FROM "ActivityCategories" ac
                        WHERE CONCAT(',', activitiesids, ',') LIKE CONCAT('%,',ac."Id", ',%') OR ac."Id" = activityid

                    UNION ALL

                        SELECT
                          ac."Id"
                        , ac."Code"
                        , ac."DicParentId"
                        , ac."IsDeleted"
                        , ac."Name"
                        , ac."NameLanguage1"
                        , ac."NameLanguage2"
                        , ac."ParentId"
                        , ac."Section"
                        , ac."VersionId"
                        , ac."ActivityCategoryLevel"
                    FROM "ActivityCategories" ac
                        INNER JOIN "ActivityCte"
                    ON "ActivityCte"."Id" = ac."ParentId")

                    SELECT * FROM "ActivityCte");
                END;
                $BODY$;
                """;


            const string dropFunctionGetRegionChildren =
                """
                DROP FUNCTION IF EXISTS "GetRegionChildren"(regionId integer);
                """;

            const string createFunctionGetRegionChildren =
                """
                CREATE OR REPLACE FUNCTION "GetRegionChildren"(regionId integer)
                RETURNS TABLE("Id" integer, "AdminstrativeCenter" text, "Code" text, "IsDeleted" boolean, "Name" text, "NameLanguage1" text, "NameLanguage2" text, "ParentId" integer, "FullPath" text, "FullPathLanguage1" text, "FullPathLanguage2" text, "RegionLevel" integer)
                LANGUAGE 'plpgsql'
                AS
                $BODY$
                BEGIN
                    RETURN QUERY
                (
                    WITH RECURSIVE "RegionsCte" AS
                    (
                        SELECT
                          r."Id"
                        , r."AdminstrativeCenter"
                        , r."Code"
                        , r."IsDeleted"
                        , r."Name"
                        , r."NameLanguage1"
                        , r."NameLanguage2"
                        , r."ParentId"
                        , r."FullPath"
                        , r."FullPathLanguage1"
                        , r."FullPathLanguage2"
                        , r."RegionLevel"
                    FROM "Regions" r
                    WHERE r."Id" = regionId

                    UNION ALL

                    SELECT
                          r."Id"
                        , r."AdminstrativeCenter"
                        , r."Code"
                        , r."IsDeleted"
                        , r."Name"
                        , r."NameLanguage1"
                        , r."NameLanguage2"
                        , r."ParentId"
                        , r."FullPath"
                        , r."FullPathLanguage1"
                        , r."FullPathLanguage2"
                        , r."RegionLevel"
                    FROM "Regions" r
                        INNER JOIN "RegionsCte" rc
                        ON rc."Id" = r."ParentId"
                    )

                SELECT * FROM "RegionsCte"
                );
                END;
                $BODY$;
                """;


            const string dropFunctionGetRegionParent =
                """
                DROP FUNCTION IF EXISTS "GetRegionParent";
                """;


            // Notice that level could be a SMALLINT, but that would require a cast
            // when using the function, so we use an INTEGER.
            const string createFunctionGetRegionParent =
                """
                CREATE OR REPLACE FUNCTION "GetRegionParent"(regionid INTEGER, level INTEGER)
                RETURNS INTEGER
                LANGUAGE 'plpgsql'
                AS $BODY$
                DECLARE
                    res INTEGER;
                BEGIN
                    WITH RECURSIVE region_tree AS
                    (
                        SELECT id, parentid, 0 AS lvl
                        FROM "Regions"
                        WHERE id = regionid
                        UNION ALL
                        SELECT r.id, r.parentid, lvl + 1
                        FROM region_tree AS p
                        INNER JOIN regions r ON p.parentid = r.id
                    ),
                    region_tree_levels AS
                    (
                        SELECT row_number() OVER (ORDER BY lvl DESC) AS level,
                        region_tree.*
                        FROM region_tree
                    )
                    SELECT id INTO res
                    FROM region_tree_levels
                    WHERE level = $2;

                    RETURN res;
                END;
                $BODY$;
                """;


            const string dropFunctionGetActivityParent =
                """
                DROP FUNCTION IF EXISTS "GetActivityParent";
                """;


            // Notice that level could be a SMALLINT, but that would require a cast
            // when using the function, so we use an INTEGER.
            const string createFunctionGetActivityParent =
                """
                CREATE OR REPLACE FUNCTION "GetActivityParent"(
                    activity_id INTEGER,
                    level INTEGER,
                    param_name VARCHAR(50)
                )
                RETURNS VARCHAR(2000)
                LANGUAGE 'plpgsql'
                AS $BODY$
                DECLARE
                    res VARCHAR(2000);
                BEGIN
                    WITH RECURSIVE
                    activity_tree AS
                    (
                        SELECT id, parentid, 0 AS lvl, Code, "Name"
                        FROM "ActivityCategories"
                        WHERE id = activity_id

                        UNION ALL

                        SELECT ac.id, ac.parentid, tr.lvl + 1, ac.Code, ac."Name"
                        FROM activity_tree tr
                        JOIN "ActivityCategories" ac ON tr.parentid = ac.id
                    ),

                    activity_levels AS
                    (
                        SELECT ROW_NUMBER() OVER (ORDER BY lvl DESC) AS level,
                        tr.*
                        FROM activity_tree tr
                    )

                    SELECT INTO res
                        CASE LOWER(param_name)
                            WHEN 'code' THEN "Code"
                            WHEN 'name' THEN "Name"
                        END
                    FROM activity_levels
                    WHERE level = level;

                    RETURN res;
                END;
                $BODY$;
                """;


            const string dropFunctionGetSectorParent =
                """
                DROP FUNCTION IF EXISTS "GetSectorParent";
                """;


            // Notice that level could be a SMALLINT, but that would require a cast
            // when using the function, so we use an INTEGER.
            const string createFunctionGetSectorParent =
                """
                CREATE OR REPLACE FUNCTION "GetSectorParent"(
                    sector_id INTEGER,
                    level INTEGER,
                    param_name VARCHAR(50)
                )
                RETURNS VARCHAR(2000)
                LANGUAGE 'plpgsql'
                AS $BODY$
                DECLARE
                    res VARCHAR(2000);
                BEGIN
                    WITH RECURSIVE
                    sector_tree AS
                    (
                        SELECT id, parentid, 0 AS lvl, Code, "Name"
                        FROM "SectorCodes" sc
                        WHERE id = sector_id

                        UNION ALL

                        SELECT sc.id, sc.parentid, tr.lvl + 1, sc.Code, sc."Name"
                        FROM sector_tree tr
                        JOIN "SectorCodes" sc ON tr.parentid = sc.id
                    ),

                    sector_levels AS
                    (
                        SELECT ROW_NUMBER() OVER (ORDER BY lvl DESC) AS level,
                        tr.*
                        FROM sector_tree tr
                    )

                    SELECT INTO res
                        CASE LOWER(param_name)
                            WHEN 'code' THEN "Code"
                            WHEN 'name' THEN "Name"
                        END
                    FROM sector_levels
                    WHERE level = level;

                    RETURN res;
                END;
                $BODY$;
                """;

            const string dropStatUnitEnterpriseView =
                """
                DROP VIEW IF EXISTS "V_StatUnitEnterprise_2021";
                """;


            const string createStatUnitEnterpriseView =
                """
                CREATE VIEW "V_StatUnitEnterprise_2021"
                AS
                    SELECT
                        stu."StatId",
                        COALESCE("GetRegionParent"(aad."Region_id", 1), aad."Region_id") "Oblast",
                        COALESCE("GetRegionParent"(aad."Region_id", 2), aad."Region_id") "Rayon",
                        "GetActivityParent"(acg."Id", 1, 'code') "ActCat_section_code",
                        "GetActivityParent"(acg."Id", 1, 'name') "ActCat_section_desc",
                        "GetActivityParent"(acg."Id", 2, 'code') "ActCat_2dig_code",
                        "GetActivityParent"(acg."Id", 2, 'name') "ActCat_2dig_desc",
                        "GetActivityParent"(acg."Id", 3, 'code') "ActCat_3dig_code",
                        "GetActivityParent"(acg."Id", 3, 'name') "ActCat_3dig_desc",
                        lfm."Code" "LegalForm_code",
                        lfm."Name" "LegalForm_desc",
                        "GetSectorParent"(stu."InstSectorCodeId", 1, 'code') "InstSectorCode_level1",
                        "GetSectorParent"(stu."InstSectorCodeId", 1, 'name') "InstSectorCode_level1_desc",
                        "GetSectorParent"(stu."InstSectorCodeId", 2, 'code') "InstSectorCode_level2",
                        "GetSectorParent"(stu."InstSectorCodeId", 2, 'name') "InstSectorCode_level2_desc",
                        uns."Code" "SizeCode",
                        uns."Name" "SizeDesc",
                        CASE
                            WHEN (stu."TurnoverYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1
                                  OR EXTRACT(YEAR FROM stu."TurnoverDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1)
                            THEN stu."Turnover"
                            ELSE NULL
                        END "Turnover",
                        CASE
                            WHEN (stu."EmployeesYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1
                                  OR EXTRACT(YEAR FROM stu."EmployeesDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1)
                            THEN act."Employees"
                            ELSE NULL
                        END "Employees",
                        CASE
                            WHEN (stu."EmployeesYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1
                                  OR EXTRACT(YEAR FROM stu."EmployeesDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1)
                            THEN stu."NumOfPeopleEmp"
                            ELSE NULL
                        END "NumOfPeopleEmp",
                        stu."RegistrationDate",
                        stu."LiqDate",
                        sts."Code" "StatusCode",
                        sts."Name" "StatusDesc",
                        psn."Sex"
                    FROM
                        "StatisticalUnits" stu
                        LEFT JOIN "Address" aad ON stu."ActualAddressId" = aad."Address_id"
                        LEFT JOIN "ActivityStatisticalUnits" asu ON stu."RegId" = asu."Unit_Id"
                        LEFT JOIN "Activities" act ON asu."Activity_Id" = act."Id"
                        LEFT JOIN "ActivityCategories" acg ON act."ActivityCategoryId" = acg."Id"
                        LEFT JOIN "LegalForms" lfm ON stu."LegalFormId" = lfm."Id"
                        LEFT JOIN "UnitSizes" uns ON stu."SizeId" = uns."Id"
                        LEFT JOIN "PersonStatisticalUnits" psu ON stu."RegId" = psu."Unit_Id" AND psu."PersonTypeId" = 3 --manager
                        LEFT JOIN "Persons" psn ON psu."Person_Id" = psn."Id"
                        LEFT JOIN "UnitStatuses" sts ON stu."UnitStatusId" = sts."Id"
                    WHERE
                        LOWER(stu."Discriminator") = 'enterpriseunit'
                """;


            const string dropStatUnitLocalView =
                """
                DROP VIEW IF EXISTS "V_StatunitLocal_2021";
                """;


            const string createStatUnitLocalView =
                """
                CREATE OR REPLACE VIEW "V_StatunitLocal_2021" AS
                SELECT
                    stu."StatId",
                    COALESCE("GetRegionParent"(aad."Region_id",1), aad."Region_id") AS oblast,
                    COALESCE("GetRegionParent"(aad."Region_id",2), aad."Region_id") AS rayon,
                    "GetActivityParent"(acg."Id",1,'code') AS actcat_section_code,
                    "GetActivityParent"(acg."Id",1,'name') AS actcat_section_desc,
                    "GetActivityParent"(acg."Id",2,'code') AS actcat_2dig_code,
                    "GetActivityParent"(acg."Id",2,'name') AS actcat_2dig_desc,
                    "GetActivityParent"(acg."Id",3,'code') AS actcat_3dig_code,
                    "GetActivityParent"(acg."Id",3,'name') AS actcat_3dig_desc,
                    lfm."Code" AS legalform_code,
                    lfm."Name" AS legalform_desc,
                    "GetSectorParent"(stu."InstSectorCodeId",1,'code') AS instsectorcode_level1,
                    "GetSectorParent"(stu."InstSectorCodeId",1,'name') AS instsectorcode_level1_desc,
                    "GetSectorParent"(stu."InstSectorCodeId",2,'code') AS instsectorcode_level2,
                    "GetSectorParent"(stu."InstSectorCodeId",2,'name') AS instsectorcode_level2_desc,
                    uns."Code" AS sizecode,
                    uns."Name" AS sizedesc,
                    CASE
                        WHEN (stu."TurnoverYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1 OR EXTRACT(YEAR FROM stu."TurnoverDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1) THEN stu."Turnover"
                        ELSE NULL
                    END AS turnover,
                    CASE
                        WHEN (stu."EmployeesYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1 OR EXTRACT(YEAR FROM stu."EmployeesDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1) THEN act."Employees"
                        ELSE NULL
                    END AS employees,
                    CASE
                        WHEN (stu."EmployeesYear" = EXTRACT(YEAR FROM CURRENT_DATE) - 1 OR EXTRACT(YEAR FROM stu."EmployeesDate") = EXTRACT(YEAR FROM CURRENT_DATE) - 1) THEN stu."NumOfPeopleEmp"
                        ELSE NULL
                    END AS numofpeopleemp,
                    stu."RegistrationDate",
                    stu."LiqDate",
                    sts."Code" AS statuscode,
                    sts."Name" AS statusdesc,
                    psn."Sex"
                FROM
                    "StatisticalUnits" stu
                    LEFT JOIN "Address" aad ON stu."ActualAddressId" = aad."Address_id"
                    LEFT JOIN "ActivityStatisticalUnits" asu ON stu."RegId" = asu."Unit_Id"
                    LEFT JOIN "Activities" act ON asu."Activity_Id" = act."Id"
                    LEFT JOIN "ActivityCategories" acg ON act."ActivityCategoryId" = acg."Id"
                    LEFT JOIN "LegalForms" lfm ON stu."LegalFormId" = lfm."Id"
                    LEFT JOIN "UnitSizes" uns ON stu."SizeId" = uns."Id"
                    LEFT JOIN "PersonStatisticalUnits" psu ON stu."RegId" = psu."Unit_Id" AND psu."PersonTypeId" = 3 --manager
                    LEFT JOIN "Persons" psn ON psu."Person_Id" = psn."Id"
                    LEFT JOIN "UnitStatuses" sts ON stu."UnitStatusId" = sts."Id"
                WHERE
                    LOWER(stu."Discriminator") = 'localunit';
                """;



            #endregion

            context.Database.ExecuteSqlRaw(dropStatUnitSearchView);
            context.Database.ExecuteSqlRaw(createStatUnitSearchView);

            context.Database.ExecuteSqlRaw(dropProcedureGetReportsTree);
#pragma warning disable EF1000 // Possible SQL injection vulnerability.
            context.Database.ExecuteSqlRaw(createProcedureGetReportsTree);
#pragma warning restore EF1000 // Possible SQL injection vulnerability.

            context.Database.ExecuteSqlRaw(dropStatUnitLocalView);
            context.Database.ExecuteSqlRaw(dropStatUnitEnterpriseView);
            context.Database.ExecuteSqlRaw(dropFunctionGetActivityChildren);
            context.Database.ExecuteSqlRaw(dropFunctionGetRegionChildren);
            context.Database.ExecuteSqlRaw(dropFunctionGetRegionParent);
            context.Database.ExecuteSqlRaw(dropFunctionGetActivityParent);
            context.Database.ExecuteSqlRaw(dropFunctionGetSectorParent);

            context.Database.ExecuteSqlRaw(createFunctionGetActivityChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetRegionChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetRegionParent);
            context.Database.ExecuteSqlRaw(createFunctionGetActivityParent);
            context.Database.ExecuteSqlRaw(createFunctionGetSectorParent);
            context.Database.ExecuteSqlRaw(createStatUnitEnterpriseView);
            context.Database.ExecuteSqlRaw(createStatUnitLocalView);
        }
    }
}
