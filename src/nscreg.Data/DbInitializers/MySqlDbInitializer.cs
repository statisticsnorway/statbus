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
                    StartPeriod,
                    ParentId,
                    IsDeleted,
                    LiqReason,
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
                    InstSectorCodeId AS SectorCodeId,
                    LegalFormId,
                    DataSourceClassificationId,
                    StartPeriod,
                    ParentId,
                    IsDeleted,
                    LiqReason,
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
                WITH RECURSIVE ActivityCte (Id, Code, DicParentId, IsDeleted, Name, ParentId, Section, VersionId) AS 
	                  (
		                SELECT 
		                   Id
		                  ,Code
		                  ,DicParentId
		                  ,IsDeleted
		                  ,Name
		                  ,ParentId
		                  ,Section
		                  ,VersionId
		                FROM ActivityCategories
		                WHERE Id = activityId

		                UNION ALL

		                SELECT 
		                   ac.Id
		                  ,ac.Code
		                  ,ac.DicParentId
		                  ,ac.IsDeleted
		                  ,ac.Name
		                  ,ac.ParentId
		                  ,ac.Section
		                  ,ac.VersionId
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
	                 WITH RECURSIVE RegionsCte (Id, AdminstrativeCenter, Code, IsDeleted, Name, ParentId, FullPath) AS 
	                  (
		                SELECT 
		                   Id
		                  ,AdminstrativeCenter
		                  ,Code
		                  ,IsDeleted
		                  ,Name
		                  ,ParentId
		                  ,FullPath
		                FROM Regions
		                WHERE Id = regionId

		                UNION ALL

		                SELECT 
		                   r.Id
		                  ,r.AdminstrativeCenter
		                  ,r.Code
		                  ,r.IsDeleted
		                  ,r.Name
		                  ,r.ParentId
		                  ,r.FullPath
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
