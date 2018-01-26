using Microsoft.EntityFrameworkCore;
using System.Linq;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;

namespace nscreg.Data
{
    /// <summary>
    /// Класс инициализации данных в БД
    /// </summary>
    public static class NscRegDbInitializer
    {
        /// <summary>
        /// Drop database if exists and create new one, then apply migrations
        /// </summary>
        /// <param name="context"></param>
        public static void RecreateDb(NSCRegDbContext context)
        {
            context.Database.EnsureDeleted();
            context.Database.Migrate();
        }
        
        /// <summary>
        /// Drop and re-create statunit search view
        /// </summary>
        /// <param name="context"></param>
        /// <param name="provider"></param>
        public static void CreateStatUnitSearchView(NSCRegDbContext context, ConnectionProvider provider)
        {
            #region Scripts

            const string dropStatUnitSearchViewTable = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE V_StatUnitSearch";

            const string dropStatUnitSearchViewTableSqliteInmemory = @"
                DROP TABLE V_StatUnitSearch";

            const string dropStatUnitSearchView = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'V_StatUnitSearch'  AND TABLE_TYPE = 'VIEW')
                DROP VIEW [dbo].[V_StatUnitSearch]";

            const string dropStatUnitSearchViewSqliteInmemory = @"
                DROP VIEW IF EXISTS V_StatUnitSearch";

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
                FROM	dbo.EnterpriseGroups
                    LEFT JOIN dbo.Address
                        ON AddressId = Address_id
            ";

            const string createStatUnitSearchViewSqliteInmemory = @"
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

            const string dropReportTreeTable = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'ReportTree' AND TABLE_TYPE = 'BASE TABLE')
                DROP TABLE ReportTree";

            const string dropProcedureGetReportsTree = @"
                IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'GetReportsTree' AND ROUTINE_TYPE = 'PROCEDURE')
                DROP PROCEDURE GetReportsTree";

            const string dropReportTreeTableSqliteInmemory = @"
                DROP TABLE ReportTree";

            const string createProcedureGetReportsTree = @"
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
		                FROM OPENQUERY(WALLET,
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

            #endregion

            if (provider == ConnectionProvider.InMemory)
            {
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTableSqliteInmemory);
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewSqliteInmemory);
                context.Database.ExecuteSqlCommand(createStatUnitSearchViewSqliteInmemory);
                context.Database.ExecuteSqlCommand(dropReportTreeTableSqliteInmemory);
            }
            else
            {
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTable);
                context.Database.ExecuteSqlCommand(dropStatUnitSearchView);
                context.Database.ExecuteSqlCommand(createStatUnitSearchView);
                context.Database.ExecuteSqlCommand(dropReportTreeTable);
                context.Database.ExecuteSqlCommand(dropProcedureGetReportsTree);
                context.Database.ExecuteSqlCommand(createProcedureGetReportsTree);
            }
        }

        /// <summary>
        /// Add or ensure System Administrator role and its access rules
        /// </summary>
        /// <param name="context"></param>
        public static void EnsureRoles(NSCRegDbContext context) => SeedData.AddUsersAndRoles(context);

        /// <summary>
        /// Метод инициализации данных в БД
        /// </summary>
        /// <param name="context"></param>
        public static void Seed(NSCRegDbContext context)
        {
            if (!context.Regions.Any()) SeedData.AddRegions(context);

            if (!context.ActivityCategories.Any()) SeedData.AddActivityCategories(context);

            if (!context.LegalForms.Any())
            {
                context.LegalForms.Add(new LegalForm {Name = "Хозяйственные товарищества и общества"});
                context.SaveChanges();
                var lf = context.LegalForms
                    .Where(x => x.Name == "Хозяйственные товарищества и общества")
                    .Select(x => x.Id)
                    .SingleOrDefault();
                context.LegalForms.AddRange(new LegalForm {Name = "Акционерное общество", ParentId = lf});
                context.SaveChanges();
            }

            if (!context.SectorCodes.Any()) SeedData.AddSectorCodes(context);

            if (!context.StatisticalUnits.Any()) SeedData.AddStatUnits(context);

            if (!context.DataSources.Any()) SeedData.AddDataSources(context);

            if (!context.LegalForms.Any()) SeedData.AddLegalForms(context);

            if (!context.Countries.Any()) SeedData.AddCountries(context);

            if (!context.AnalysisLogs.Any()) SeedData.AddAnalysisLogs(context);
        }
    }
}
