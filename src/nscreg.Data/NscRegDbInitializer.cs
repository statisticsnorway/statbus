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
        public static void RecreateDb(NSCRegDbContext context)
        {
            context.Database.EnsureDeleted();
            context.Database.Migrate();
        }

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
                    DataSource,
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
                    DataSource,
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
                    DataSource,
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
                    DataSource,
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

            #endregion

            if (provider == ConnectionProvider.InMemory)
            {
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTableSqliteInmemory);
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewSqliteInmemory);
                context.Database.ExecuteSqlCommand(createStatUnitSearchViewSqliteInmemory);
            }
            else
            {
                context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTable);
                context.Database.ExecuteSqlCommand(dropStatUnitSearchView);
                context.Database.ExecuteSqlCommand(createStatUnitSearchView);
            }
        }

        /// <summary>
        /// Метод инициализации данных в БД
        /// </summary>
        /// <param name="context"></param>
        public static void Seed(NSCRegDbContext context)
        {
            SeedData.AddUsersAndRoles(context);

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
        }
    }
}
