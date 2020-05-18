using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
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
                    Region_id AS RegionId,
                    Employees,
                    Turnover,
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

        const string dropReportTreeTableSqliteInmemory = @"
                DROP TABLE ReportTree";

        #endregion

        public void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null)
        {
            context.Database.ExecuteSqlCommand(dropStatUnitSearchViewTableSqliteInmemory);
            context.Database.ExecuteSqlCommand(dropStatUnitSearchViewSqliteInmemory);
            context.Database.ExecuteSqlCommand(createStatUnitSearchViewSqliteInmemory);
            context.Database.ExecuteSqlCommand(dropReportTreeTableSqliteInmemory);
        }
    }
}
