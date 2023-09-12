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

            const string dropStatUnitSearchViewTable =
                """
                DROP TABLE IF EXISTS "V_StatUnitSearch";
                """;

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
                    "TaxRegId",
                    "StatId",
                    "ExternalId",
                    "addr"."Region_id" AS "RegionId",
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
                    "addr"."Address_id" AS "AddressId",
                    "addr"."Address_part1" AS "AddressPart1",
                    "addr"."Address_part2" AS "AddressPart2",
                    "addr"."Address_part3" AS "AddressPart3",
                    "act_addr"."Address_id" AS "ActualAddressId",
                    "act_addr"."Address_part1" AS "ActualAddressPart1",
                    "act_addr"."Address_part2" AS "ActualAddressPart2",
                    "act_addr"."Address_part3" AS "ActualAddressPart3",
                     CASE
                         WHEN "Discriminator" = 'LocalUnit' THEN 1
                         WHEN "Discriminator" = 'LegalUnit' THEN 2
                         WHEN "Discriminator" = 'EnterpriseUnit' THEN 3
                    END AS "UnitType"
                FROM    "StatisticalUnits"
                LEFT JOIN "Address" as "addr" ON "AddressId" = "Address_id"
                LEFT JOIN "Address" as "act_addr" ON "ActualAddressId" = "act_addr"."Address_id"

                UNION ALL

                SELECT
                    "RegId",
                    "Name",
                    "TaxRegId",
                    "StatId",
                    "ExternalId",
                    "addr"."Region_id" AS "RegionId",
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
                    "addr"."Address_id" AS "AddressId",
                    "addr"."Address_part1" AS "AddressPart1",
                    "addr"."Address_part2" AS "AddressPart2",
                    "addr"."Address_part3" AS "AddressPart3",
                    "act_addr"."Address_id" AS "ActualAddressId",
                    "act_addr"."Address_part1" AS "ActualAddressPart1",
                    "act_addr"."Address_part2" AS "ActualAddressPart2",
                    "act_addr"."Address_part3" AS "ActualAddressPart3",
                    4 AS "UnitType"
                FROM "EnterpriseGroups"
                LEFT JOIN "Address" as "addr" ON "AddressId" = "Address_id"
                LEFT JOIN "Address" as "act_addr" ON "ActualAddressId" = "act_addr"."Address_id"
                """;

            const string dropReportTreeTable =
                """
                DROP TABLE IF EXISTS "ReportTree";
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
                $$
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
                $$;
                """;
            #endregion


            context.Database.ExecuteSqlRaw(dropStatUnitSearchViewTable);
            context.Database.ExecuteSqlRaw(dropStatUnitSearchView);
            context.Database.ExecuteSqlRaw(createStatUnitSearchView);
            context.Database.ExecuteSqlRaw(dropReportTreeTable);
            context.Database.ExecuteSqlRaw(dropFunctionGetActivityChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetActivityChildren);
            context.Database.ExecuteSqlRaw(dropFunctionGetRegionChildren);
            context.Database.ExecuteSqlRaw(createFunctionGetRegionChildren);
        }
    }
}
