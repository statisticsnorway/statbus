using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class MySqlDbInitializer : IDbInitializer
    {
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            #region Scripts

            const string dropStatUnitSearchViewTable = @"DROP TABLE IF EXISTS V_StatUnitSearch;";

            const string dropStatUnitSearchView = @"DROP VIEW IF EXISTS V_StatUnitSearch;";

            const string createStatUnitSearchView = @"
                CREATE VIEW V_StatUnitSearch
                AS
                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
                    Region_id AS RegionId,
                    Employees,
                    Turnover,
                    InstSectorCodeId AS SectorCodeId,
                    LegalFormId,
                    DataSourceClassificationId,
                    ChangeReason,
                    StartPeriod,
                    IsDeleted,
                    LiqReason,
                    LiqDate,
                    Address_part1 AS AddressPart1,
                    Address_part2 AS AddressPart2,
                    Address_part3 AS AddressPart3,
                    CASE
                        WHEN Discriminator = 'LocalUnit' THEN 1
                        WHEN Discriminator = 'LegalUnit' THEN 2
                        WHEN Discriminator = 'EnterpriseUnit' THEN 3

                    END
                    AS UnitType
                FROM	StatisticalUnits
                    LEFT JOIN Address
                        ON AddressId = Address_id

                UNION ALL

                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
                    Region_id AS RegionId,
                    Employees,
                    Turnover,
                    NULL AS SectorCodeId,
                    NULL AS LegalFormId,
                    DataSourceClassificationId,
                    ChangeReason,
                    StartPeriod,
                    IsDeleted,
                    LiqReason,
                    LiqDateEnd,
                    Address_part1 AS AddressPart1,
                    Address_part2 AS AddressPart2,
                    Address_part3 AS AddressPart3,
                    4 AS UnitType
                FROM	EnterpriseGroups
                    LEFT JOIN Address
                        ON AddressId = Address_id;
            ";

            const string dropReportTreeTable = @"DROP TABLE IF EXISTS ReportTree;";

            const string dropProcedureGetActivityChildren = @"DROP PROCEDURE IF EXISTS GetActivityChildren;";

            const string createProcedureGetActivityChildren = @"
                CREATE PROCEDURE GetActivityChildren (activityId INT)
                BEGIN
                WITH RECURSIVE ActivityCte (Id, Code, DicParentId, IsDeleted, Name, NameLanguage1, NameLanguage2, ParentId, Section, VersionId, ActivityCategoryLevel) AS 
	                  (
		                SELECT 
		                   Id
		                  ,Code
		                  ,DicParentId
		                  ,IsDeleted
		                  ,Name
                          ,NameLanguage1
                          ,NameLanguage2
		                  ,ParentId
		                  ,Section
		                  ,VersionId
                          ,ActivityCategoryLevel
		                FROM ActivityCategories
		                WHERE Id = activityId

		                UNION ALL

		                SELECT 
		                   ac.Id
		                  ,ac.Code
		                  ,ac.DicParentId
		                  ,ac.IsDeleted
		                  ,ac.Name
                          ,ac.NameLanguage1
                          ,ac.NameLanguage2
		                  ,ac.ParentId
		                  ,ac.Section
		                  ,ac.VersionId
                          ,ac.ActivityCategoryLevel
		                FROM ActivityCategories ac
			                INNER JOIN ActivityCte  
			                ON ActivityCte.Id = ac.ParentId
		
	                )

	                SELECT * FROM ActivityCte;
            END;";

            const string dropProcedureGetRegionChildren = @"DROP PROCEDURE IF EXISTS GetRegionChildren;";

            const string createProcedureGetRegionChildren = @"
                CREATE PROCEDURE GetRegionChildren(regionId INT)
                BEGIN
	                 WITH RECURSIVE RegionsCte (Id, AdminstrativeCenter, Code, IsDeleted, Name, NameLanguage1, NameLanguage2, ParentId, FullPath, FullPathLanguage1, FullPathLanguage2, RegionLevel) AS 
	                  (
		                SELECT 
		                   Id
		                  ,AdminstrativeCenter
		                  ,Code
		                  ,IsDeleted
		                  ,Name
                          ,NameLanguage1
                          ,NameLanguage2
		                  ,ParentId
		                  ,FullPath
                          ,FullPathLanguage1
                          ,FullPathLanguage2
                          ,RegionLevel
		                FROM Regions
		                WHERE Id = regionId

		                UNION ALL

		                SELECT 
		                   r.Id
		                  ,r.AdminstrativeCenter
		                  ,r.Code
		                  ,r.IsDeleted
		                  ,r.Name
                          ,r.NameLanguage1
                          ,r.NameLanguage2
		                  ,r.ParentId
		                  ,r.FullPath
                          ,r.FullPathLanguage1
                          ,r.FullPathLanguage2
                          ,r.RegionLevel
		                FROM Regions r
			                INNER JOIN RegionsCte rc
			                ON rc.Id = r.ParentId
		
	                  )

	                 SELECT * FROM RegionsCte;
                END";

            #endregion

            context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTable);
            context.Database.ExecuteSqlCommand(dropStatUnitSearchView);
            context.Database.ExecuteSqlCommand(createStatUnitSearchView);
            context.Database.ExecuteSqlCommand(dropReportTreeTable);
            context.Database.ExecuteSqlCommand(dropProcedureGetActivityChildren);
            context.Database.ExecuteSqlCommand(createProcedureGetActivityChildren);
            context.Database.ExecuteSqlCommand(dropProcedureGetRegionChildren);
            context.Database.ExecuteSqlCommand(createProcedureGetRegionChildren);
        }
    }
}
