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
                    addr.Region_id AS RegionId,
                    act_addr.Region_id AS ActualAddressRegionId,
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
                    act_addr.Address_id AS ActualAddressId,
                    act_addr.Address_part1 AS ActualAddressPart1,
                    act_addr.Address_part2 AS ActualAddressPart2,
                    act_addr.Address_part3 AS ActualAddressPart3,
                    CASE
                        WHEN Discriminator = 'LocalUnit' THEN 1
                        WHEN Discriminator = 'LegalUnit' THEN 2
                        WHEN Discriminator = 'EnterpriseUnit' THEN 3
                    END
                    AS UnitType
                FROM	StatisticalUnits      
                    LEFT JOIN Address as act_addr
                        ON ActualAddressId = act_addr.Address_id

                UNION ALL

                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
                    addr.Region_id AS RegionId,
                    act_addr.Region_id AS ActualAddressRegionId,
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
                    act_addr.Address_id AS ActualAddressId,
                    act_addr.Address_part1 AS ActualAddressPart1,
                    act_addr.Address_part2 AS ActualAddressPart2,
                    act_addr.Address_part3 AS ActualAddressPart3,
                    4 AS UnitType
                FROM	EnterpriseGroups
                    LEFT JOIN Address as act_addr
                        ON ActualAddressId = act_addr.Address_id;
            ";

            const string dropReportTreeTable = @"DROP TABLE IF EXISTS ReportTree;";

            const string dropProcedureGetActivityChildren = @"DROP PROCEDURE IF EXISTS GetActivityChildren;";

            const string createProcedureGetActivityChildren = @"
                CREATE PROCEDURE GetActivityChildren (activityId INT, activitiesIds VARCHAR(400))
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
		                WHERE CONCAT(',', activitiesIds, ',') LIKE CONCAT('%,',Id, ',%') OR Id = activityId

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

            context.Database.ExecuteSqlInterpolated($"{dropStatUnitSearchViewTable}");
            context.Database.ExecuteSqlInterpolated($"{dropStatUnitSearchView}");
            context.Database.ExecuteSqlInterpolated($"{createStatUnitSearchView}");
            context.Database.ExecuteSqlInterpolated($"{dropReportTreeTable}");
            context.Database.ExecuteSqlInterpolated($"{dropProcedureGetActivityChildren}");
            context.Database.ExecuteSqlInterpolated($"{createProcedureGetActivityChildren}");
            context.Database.ExecuteSqlInterpolated($"{dropProcedureGetRegionChildren}");
            context.Database.ExecuteSqlInterpolated($"{createProcedureGetRegionChildren}");
        }
    }
}
