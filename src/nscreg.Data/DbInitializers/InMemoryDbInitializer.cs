using Microsoft.EntityFrameworkCore;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public class InMemoryDbInitializer : IDbInitializer
    {
        #region Scripts
        const string dropStatUnitSearchViewTableSqliteInmemory = @"
                DROP TABLE V_StatUnitSearch";

        const string dropStatUnitSearchViewSqliteInmemory = @"
                DROP VIEW IF EXISTS V_StatUnitSearch";

        const string createStatUnitSearchViewSqliteInmemory = @"
                CREATE VIEW V_StatUnitSearch
                AS
                SELECT
                    RegId,
                    Name,
                    TaxRegId,
                    StatId,
                    ExternalId,
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
                    act_addr.Address_part1 AS ActualAddressPart1,
                    act_addr.Address_part2 AS ActualAddressPart2,
                    act_addr.Address_part3 AS ActualAddressPart3,
                    4 AS UnitType
                FROM	EnterpriseGroups                    
                    LEFT JOIN Address as act_addr
                        ON ActualAddressId = act_addr.Address_id
            ";

        const string dropReportTreeTableSqliteInmemory = @"
                DROP TABLE ReportTree";

        #endregion

        [System.Obsolete]
        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            context.Database.ExecuteSqlRaw(dropStatUnitSearchViewTableSqliteInmemory);
            context.Database.ExecuteSqlRaw(dropStatUnitSearchViewSqliteInmemory);
            context.Database.ExecuteSqlRaw(createStatUnitSearchViewSqliteInmemory);
            context.Database.ExecuteSqlRaw(dropReportTreeTableSqliteInmemory);
        }
    }
}
