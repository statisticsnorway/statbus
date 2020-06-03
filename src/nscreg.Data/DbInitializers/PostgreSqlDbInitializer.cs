using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class PostgreSqlDbInitializer : IDbInitializer
    {
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            #region Scripts

            const string dropStatUnitSearchViewTable = @"DO
                                                         $$
                                                         BEGIN
                                                         IF EXISTS 
                                                         (
                                                         	SELECT 1
                                                         	FROM information_schema.tables 
                                                         	WHERE table_name = 'V_StatUnitSearch'
                                                         	AND table_type = 'BASE TABLE'
                                                         )
                                                         THEN 
                                                         DROP TABLE ""V_StatUnitSearch"";
                                                         END IF;
                                                         END
                                                         $$ language 'plpgsql'";

            const string dropStatUnitSearchView = @"DO
                                                    $$
                                                    BEGIN
                                                    IF EXISTS 
                                                    (
                                                    	SELECT 1
                                                    	FROM information_schema.tables 
                                                    	WHERE table_name = 'V_StatUnitSearch'
                                                    	AND table_type = 'VIEW'
                                                    )
                                                    THEN 
                                                    DROP VIEW ""V_StatUnitSearch"";
                                                    END IF;
                                                    END
                                                    $$ language 'plpgsql'";

            const string createStatUnitSearchView = @"
                                                    CREATE VIEW ""V_StatUnitSearch""
                                                     AS
                                                     SELECT
                                                         ""RegId"",
                                                         ""Name"",
                                                         ""TaxRegId"",
                                                         ""StatId"",
                                                         ""ExternalId"",
                                                        CASE
						                                    WHEN ""act_addr"".""Region_id"" IS NULL THEN  ""addr"".""Region_id""
						                                    ELSE ""act_addr"".""Region_id""
						                                    END AS ""RegionId"",
                                                         ""act_addr"".""Region_id"" AS ""ActualAddressRegionId"",
                                                         ""Employees"",
                                                         ""Turnover"",
                                                        ""InstSectorCodeId"" AS ""SectorCodeId"",
                                                        ""LegalFormId"",
                                                         ""DataSourceClassificationId"",
                                                         ""ChangeReason"",
                                                         ""StartPeriod"",
                                                         ""IsDeleted"",
                                                         ""LiqReason"",
                                                         ""LiqDate"",
                                                        ""addr"".""Address_id"" AS ""AddressId"",
                                                        ""addr"".""Address_part1"" AS ""AddressPart1"",
                                                        ""addr"".""Address_part2"" AS ""AddressPart2"",
                                                        ""addr"".""Address_part3"" AS ""AddressPart3"",
                                                        ""act_addr"".""Address_id"" AS ""ActualAddressId"",
                                                        ""act_addr"".""Address_part1"" AS ""ActualAddressPart1"",
                                                        ""act_addr"".""Address_part2"" AS ""ActualAddressPart2"",
                                                        ""act_addr"".""Address_part3"" AS ""ActualAddressPart3"",
                                                         CASE
                                                             WHEN ""Discriminator"" = 'LocalUnit' THEN 1
                                                             WHEN ""Discriminator"" = 'LegalUnit' THEN 2
                                                             WHEN ""Discriminator"" = 'EnterpriseUnit' THEN 3

                                                         END
                                                         AS ""UnitType""
                                                     FROM    ""StatisticalUnits""
                                                         LEFT JOIN ""Address"" as ""addr""
                                                             ON ""AddressId"" = ""Address_id""                                                        
                                                         LEFT JOIN ""Address"" as ""act_addr""
                                                             ON ""ActualAddressId"" = ""act_addr"".""Address_id""

                                                     UNION ALL

                                                     SELECT
                                                         ""RegId"",
                                                         ""Name"",
                                                         ""TaxRegId"",
                                                         ""StatId"",
                                                         ""ExternalId"",
                                                        CASE
						                                    WHEN ""act_addr"".""Region_id"" IS NULL THEN  ""addr"".""Region_id""
						                                    ELSE ""act_addr"".""Region_id""
						                                    END AS ""RegionId"",
                                                         ""act_addr"".""Region_id"" AS ""ActualAddressRegionId"",
                                                         ""Employees"",
                                                         ""Turnover"",
                                                           NULL AS ""SectorCodeId"",
                                                           NULL AS ""LegalFormId"",
                                                         ""DataSourceClassificationId"",
                                                         ""ChangeReason"",
                                                         ""StartPeriod"",
                                                         ""IsDeleted"",
                                                         ""LiqReason"",
                                                         ""LiqDateEnd"",
                                                         ""addr"".""Address_id"" AS ""AddressId"",
                                                         ""addr"".""Address_part1"" AS ""AddressPart1"",
                                                         ""addr"".""Address_part2"" AS ""AddressPart2"",
                                                         ""addr"".""Address_part3"" AS ""AddressPart3"",
                                                         ""act_addr"".""Address_id"" AS ""ActualAddressId"",
                                                         ""act_addr"".""Address_part1"" AS ""ActualAddressPart1"",
                                                         ""act_addr"".""Address_part2"" AS ""ActualAddressPart2"",
                                                         ""act_addr"".""Address_part3"" AS ""ActualAddressPart3"",
                                                         4 AS ""UnitType""
                                                     FROM    ""EnterpriseGroups""
                                                         LEFT JOIN ""Address"" as ""addr""
                                                             ON ""AddressId"" = ""Address_id""
                                                         LEFT JOIN ""Address"" as ""act_addr""
                                                             ON ""ActualAddressId"" = ""act_addr"".""Address_id""
            ";

            const string dropReportTreeTable = @"DO
                                                         $$
                                                         BEGIN
                                                         IF EXISTS 
                                                         (
                                                         	SELECT 1
                                                         	FROM information_schema.tables 
                                                         	WHERE table_name = 'ReportTree'
                                                         	AND table_type = 'BASE TABLE'
                                                         )
                                                         THEN 
                                                         DROP TABLE ""ReportTree"";
                                                         END IF;
                                                         END
                                                         $$ language 'plpgsql'";

            const string dropFunctionGetActivityChildren = @"DO
                                                            $$
                                                            BEGIN
                                                            IF EXISTS 
                                                            (
                                                            	SELECT 1
                                                            	FROM information_schema.routines 
                                                            	WHERE routine_name = 'GetActivityChildren'
                                                            	AND routine_type = 'FUNCTION'
                                                            )
                                                            THEN 
                                                            DROP FUNCTION ""GetActivityChildren"";
                                                            END IF;
                                                            END
                                                            $$ language 'plpgsql'";

            const string createFunctionGetActivityChildren = @"CREATE OR REPLACE FUNCTION public.""GetActivityChildren""(activityid integer,activitiesids varchar(400))
                                                               RETURNS TABLE(""Id"" integer, ""Code"" character varying, ""DicParentId"" integer, ""IsDeleted"" boolean, ""Name"" text, ""NameLanguage1"" text, ""NameLanguage2"" text, ""ParentId"" integer, ""Section"" character varying, ""VersionId"" integer, ""ActivityCategoryLevel"" integer) 
                                                               LANGUAGE 'plpgsql'
                                                               AS $BODY$
                                                               BEGIN
                                                                   RETURN QUERY(
                                                                   WITH RECURSIVE ""ActivityCte"" AS
                                                                   (
                                                                       SELECT
                                                                         ac.""Id""
                                                                       , ac.""Code""
                                                                       , ac.""DicParentId""
                                                                       , ac.""IsDeleted""
                                                                       , ac.""Name""
                                                                       , ac.""NameLanguage1""
                                                                       , ac.""NameLanguage2""
                                                                       , ac.""ParentId""
                                                                       , ac.""Section""
                                                                       , ac.""VersionId""
                                                                       , ac.""ActivityCategoryLevel""
                                                                       FROM ""ActivityCategories"" ac
                                                                       WHERE CONCAT(',', activitiesids, ',') LIKE CONCAT('%,',ac.""Id"", ',%') OR ac.""Id"" = activityid

                                                                   UNION ALL

                                                                       SELECT
                                                                         ac.""Id""
                                                                       , ac.""Code""
                                                                       , ac.""DicParentId""
                                                                       , ac.""IsDeleted""
                                                                       , ac.""Name""
                                                                       , ac.""NameLanguage1""
                                                                       , ac.""NameLanguage2""
                                                                       , ac.""ParentId""
                                                                       , ac.""Section""
                                                                       , ac.""VersionId""
                                                                       , ac.""ActivityCategoryLevel""
                                                                   FROM ""ActivityCategories"" ac
                                                                       INNER JOIN ""ActivityCte""
                                                                   ON ""ActivityCte"".""Id"" = ac.""ParentId"")

                                                                   SELECT * FROM ""ActivityCte"");
                                                               END;
                                                               $BODY$; ";


            const string dropFunctionGetRegionChildren = @"DO
                                                           $$
                                                           BEGIN
                                                           IF EXISTS 
                                                           (
                                                           	SELECT 1
                                                           	FROM information_schema.routines 
                                                           	WHERE routine_name = 'GetRegionChildren'
                                                           	AND routine_type = 'FUNCTION'
                                                           )
                                                           THEN 
                                                           DROP FUNCTION ""GetRegionChildren"";
                                                           END IF;
                                                           END
                                                           $$ language 'plpgsql'";

            const string createFunctionGetRegionChildren = @"CREATE OR REPLACE FUNCTION ""GetRegionChildren""(regionId integer)
                                                             RETURNS TABLE(""Id"" integer, ""AdminstrativeCenter"" text, ""Code"" text, ""IsDeleted"" boolean, ""Name"" text, ""NameLanguage1"" text, ""NameLanguage2"" text, ""ParentId"" integer, ""FullPath"" text, ""FullPathLanguage1"" text, ""FullPathLanguage2"" text, ""RegionLevel"" integer)
                                                             LANGUAGE 'plpgsql'
                                                             AS
                                                             $$
                                                             BEGIN
                                                                 RETURN QUERY
                                                             (
                                                                 WITH RECURSIVE ""RegionsCte"" AS
                                                                 (
                                                                     SELECT
                                                                       r.""Id""
                                                                     , r.""AdminstrativeCenter""
                                                                     , r.""Code""
                                                                     , r.""IsDeleted""
                                                                     , r.""Name""
                                                                     , r.""NameLanguage1""
                                                                     , r.""NameLanguage2""
                                                                     , r.""ParentId""
                                                                     , r.""FullPath""
                                                                     , r.""FullPathLanguage1""
                                                                     , r.""FullPathLanguage2""
                                                                     , r.""RegionLevel""
                                                                 FROM ""Regions"" r
                                                                 WHERE r.""Id"" = regionId

                                                                 UNION ALL

                                                                 SELECT
                                                                       r.""Id""
                                                                     , r.""AdminstrativeCenter""
                                                                     , r.""Code""
                                                                     , r.""IsDeleted""
                                                                     , r.""Name""
                                                                     , r.""NameLanguage1""
                                                                     , r.""NameLanguage2""
                                                                     , r.""ParentId""
                                                                     , r.""FullPath""
                                                                     , r.""FullPathLanguage1""
                                                                     , r.""FullPathLanguage2""
                                                                     , r.""RegionLevel""
                                                                 FROM ""Regions"" r
                                                                     INNER JOIN ""RegionsCte"" rc
                                                                     ON rc.""Id"" = r.""ParentId""
                                                                 )

                                                             SELECT * FROM ""RegionsCte""
                                                             );
                                                             END;
                                                             $$; ";
            #endregion


            context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTable);
            context.Database.ExecuteSqlCommand(dropStatUnitSearchView);
            context.Database.ExecuteSqlCommand(createStatUnitSearchView);
            context.Database.ExecuteSqlCommand(dropReportTreeTable);
            context.Database.ExecuteSqlCommand(dropFunctionGetActivityChildren);
            context.Database.ExecuteSqlCommand(createFunctionGetActivityChildren);
            context.Database.ExecuteSqlCommand(dropFunctionGetRegionChildren);
            context.Database.ExecuteSqlCommand(createFunctionGetRegionChildren);
        }
    }
}
