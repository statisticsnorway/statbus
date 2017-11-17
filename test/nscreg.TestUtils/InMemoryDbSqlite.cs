using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Data;

namespace nscreg.TestUtils
{
    public static class InMemoryDbSqlite
    {
        public static NSCRegDbContext CreateSqliteDbContext()
        {
            var ctx = new NSCRegDbContext(GetContextOptions());
            ctx.Database.EnsureCreated();

            ctx.Database.ExecuteSqlCommand(@"DROP TABLE V_StatUnitSearch");
            ctx.Database.ExecuteSqlCommand(@"DROP VIEW IF EXISTS V_StatUnitSearch");
            ctx.Database.ExecuteSqlCommand(@"CREATE VIEW V_StatUnitSearch
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
                                            ");

            return ctx;
        }

        private static DbContextOptions<NSCRegDbContext> GetContextOptions()
        {
            var serviceProvider = new ServiceCollection().AddEntityFrameworkSqlite().BuildServiceProvider();
            var builder = new DbContextOptionsBuilder<NSCRegDbContext>();
            var connection = new SqliteConnection("DataSource =:memory:");
            connection.Open();
            builder
                .UseSqlite(connection)
                .ConfigureWarnings(w => w.Ignore(InMemoryEventId.TransactionIgnoredWarning))
                .UseInternalServiceProvider(serviceProvider);
            return builder.Options;
        }
    }
}
