using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class MsSqlDbInitializer : IDbInitializer
    {
        
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            #region Scripts

            const string dropStatUnitSearchViewTable = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitSearch";



            const string dropStatUnitSearchView = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch'  AND TABLE_TYPE = 'VIEW')
                DROP VIEW [dbo].[V_StatUnitSearch]";



            const string createStatUnitSearchView = @"
                CREATE VIEW [dbo].[V_StatUnitSearch]
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
                FROM	dbo.StatisticalUnits
                    LEFT JOIN dbo.Address
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
                FROM	dbo.EnterpriseGroups
                    LEFT JOIN dbo.Address
                        ON AddressId = Address_id
            ";



            const string dropReportTreeTable = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ReportTree' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE ReportTree";

            const string dropProcedureGetReportsTree = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetReportsTree' AND ROUTINE_TYPE = 'PROCEDURE')
                DROP PROCEDURE GetReportsTree";



            string createProcedureGetReportsTree = $@"
                CREATE PROCEDURE GetReportsTree 
	                @user NVARCHAR(100)
                AS
                BEGIN
                    DECLARE @ReportTree TABLE 
	                (
		                Id INT,
		                Title NVARCHAR(500) NULL,
		                Type NVARCHAR(100) NULL,
		                ReportId INT NULL,
		                ParentNodeId INT NULL,
		                IsDeleted BIT NULL,
		                ResourceGroup NVARCHAR(100) NULL,
		                ReportUrl NVARCHAR(MAX) NULL DEFAULT ''
	                )

	                DECLARE @query NVARCHAR(1000) = N'SELECT *
		                FROM OPENQUERY({reportingSettings?.LinkedServerName},
		                ''SELECT 
			                Id,
			                Title,
			                Type,
			                ReportId,
			                ParentNodeId,
			                IsDeleted,
			                ResourceGroup,
			                NULL as ReportUrl
		                From ReportTreeNode rtn
		                Where rtn.IsDeleted = 0
			                And (rtn.ReportId is null or rtn.ReportId in (Select distinct ReportId From ReportAce where Principal = ''''' +@user+'''''))'');';

	                INSERT @ReportTree EXEC (@query)

	                SELECT * FROM @ReportTree
                END";

            const string dropFunctionGetActivityChildren = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetActivityChildren' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetActivityChildren";

            const string createFunctionGetActivityChildren = @"
                CREATE FUNCTION [dbo].[GetActivityChildren] 
                (	
	                @activityId INT
                )
                RETURNS TABLE 
                AS
                RETURN 
                (
	                  WITH ActivityCte ([Id], [Code], [DicParentId], [IsDeleted], [Name], [NameLanguage1], [NameLanguage2], [ParentId], [Section], [VersionId], [ActivityCategoryLevel]) AS 
	                  (
		                SELECT 
		                   [Id]
		                  ,[Code]
		                  ,[DicParentId]
		                  ,[IsDeleted]
		                  ,[Name]
                          ,[NameLanguage1]
                          ,[NameLanguage2]
		                  ,[ParentId]
		                  ,[Section]
		                  ,[VersionId]
                          ,[ActivityCategoryLevel]
		                FROM [dbo].[ActivityCategories]
		                WHERE [Id] = @activityId

		                UNION ALL

		                SELECT 
		                   ac.[Id]
		                  ,ac.[Code]
		                  ,ac.[DicParentId]
		                  ,ac.[IsDeleted]
		                  ,ac.[Name]
                          ,ac.[NameLanguage1]
                          ,ac.[NameLanguage2]
		                  ,ac.[ParentId]
		                  ,ac.[Section]
		                  ,ac.[VersionId]
                          ,ac.[ActivityCategoryLevel]
		                FROM [dbo].[ActivityCategories] ac
			                INNER JOIN ActivityCte  
			                ON ActivityCte.[Id] = ac.[ParentId]
		
	                )

	                SELECT * FROM ActivityCte
                )";

            const string dropFunctionGetRegionChildren = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetRegionChildren' AND ROUTINE_TYPE = 'FUNCTION')
                DROP FUNCTION GetRegionChildren";

            const string createFunctionGetRegionChildren = @"
                CREATE FUNCTION [dbo].[GetRegionChildren] 
                (	
	                @regionId INT 
                )
                RETURNS TABLE 
                AS
                RETURN 
                (
	                 WITH RegionsCte ([Id], [AdminstrativeCenter], [Code], [IsDeleted], [Name], [NameLanguage1], [NameLanguage2], [ParentId], [FullPath], [FullPathLanguage1], [FullPathLanguage2], [RegionLevel]) AS 
	                  (
		                SELECT 
		                   [Id]
		                  ,[AdminstrativeCenter]
		                  ,[Code]
		                  ,[IsDeleted]
		                  ,[Name]
                          ,[NameLanguage1]
                          ,[NameLanguage2]
		                  ,[ParentId]
		                  ,[FullPath]
                          ,[FullPathLanguage1]
                          ,[FullPathLanguage2]
                          ,[RegionLevel]
		                FROM [dbo].[Regions]
		                WHERE [Id] = @regionId

		                UNION ALL

		                SELECT 
		                   r.[Id]
		                  ,r.[AdminstrativeCenter]
		                  ,r.[Code]
		                  ,r.[IsDeleted]
		                  ,r.[Name]
                          ,r.[NameLanguage1]
                          ,r.[NameLanguage2]
		                  ,r.[ParentId]
		                  ,r.[FullPath]
                          ,r.[FullPathLanguage1]
                          ,r.[FullPathLanguage2]
                          ,r.[RegionLevel]
		                FROM [dbo].[Regions] r
			                INNER JOIN RegionsCte rc
			                ON rc.[Id] = r.[ParentId]
		
	                  )

	                 SELECT * FROM RegionsCte
                )";

            #endregion

            context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTable);
            context.Database.ExecuteSqlCommand(dropStatUnitSearchView);
            context.Database.ExecuteSqlCommand(createStatUnitSearchView);
            context.Database.ExecuteSqlCommand(dropReportTreeTable);
            context.Database.ExecuteSqlCommand(dropProcedureGetReportsTree);
#pragma warning disable EF1000 // Possible SQL injection vulnerability.
            context.Database.ExecuteSqlCommand(createProcedureGetReportsTree);
#pragma warning restore EF1000 // Possible SQL injection vulnerability.
            context.Database.ExecuteSqlCommand(dropFunctionGetActivityChildren);
            context.Database.ExecuteSqlCommand(createFunctionGetActivityChildren);
            context.Database.ExecuteSqlCommand(dropFunctionGetRegionChildren);
            context.Database.ExecuteSqlCommand(createFunctionGetRegionChildren);
        }
    }
}
