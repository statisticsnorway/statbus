using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class SearchService
    {
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;
        private readonly NSCRegDbContext _dbContext;


        public SearchService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _userService = new UserService(dbContext);
            _dbContext = dbContext;
        }

        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);
            var unit = _readCtx.LocalUnits
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Select(x => new 
                    {
                        x.RegId,
                        x.Name,
                        x.StatId,
                        x.TaxRegId,
                        x.ExternalId,
                        x.Address,
                        x.Turnover,
                        x.Employees,
                        SectorCodeId = x.InstSectorCodeId,
                        x.LegalFormId,
                        x.DataSource,
                        x.StartPeriod,
                        UnitType = StatUnitTypes.LocalUnit,
                    });
            var legalUnit = _readCtx.LegalUnits
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Select(x => new 
                    {
                        x.RegId,
                        x.Name,
                        x.StatId,
                        x.TaxRegId,
                        x.ExternalId,
                        x.Address,
                        x.Turnover,
                        x.Employees,
                        SectorCodeId = x.InstSectorCodeId,
                        x.LegalFormId,
                        x.DataSource,
                        x.StartPeriod,
                        UnitType = StatUnitTypes.LegalUnit,
                    });
            var enterpriseUnit = _readCtx.EnterpriseUnits
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Select(x => new 
                    {
                        x.RegId,
                        x.Name,
                        x.StatId,
                        x.TaxRegId,
                        x.ExternalId,
                        x.Address,
                        x.Turnover,
                        x.Employees,
                        SectorCodeId = x.InstSectorCodeId,
                        x.LegalFormId,
                        x.DataSource,
                        x.StartPeriod,
                        UnitType = StatUnitTypes.EnterpriseUnit,
                    });
            var group = _readCtx.EnterpriseGroups
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Select(x => new 
                    {
                        x.RegId,
                        x.Name,
                        x.StatId,
                        x.TaxRegId,
                        x.ExternalId,
                        x.Address,
                        x.Turnover,
                        x.Employees,
                        SectorCodeId = x.InstSectorCodeId,
                        x.LegalFormId,
                        x.DataSource,
                        x.StartPeriod,
                        UnitType = StatUnitTypes.EnterpriseGroup,
                    });


            var filtered = unit;
            switch (query.Type)
            {
                case StatUnitTypes.LocalUnit:
                    break;
                case StatUnitTypes.LegalUnit:
                    filtered = legalUnit;
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    filtered = enterpriseUnit;
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    filtered = group;
                    break;
                default:
                    filtered = unit.Concat(group).Concat(legalUnit).Concat(enterpriseUnit);
                    break;

            }

            var filter = new List<string>();
            var activities = "";

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                var wildcard = query.Wildcard.ToLower();

                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.ToLower().Contains(wildcard);
                filtered = filtered.Where(x =>
                    x.Name.ToLower().Contains(wildcard)
                    || checkWildcard(x.StatId)
                    || checkWildcard(x.TaxRegId)
                    || checkWildcard(x.ExternalId)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)));


                filter.Add($"(\"Name\" IS NOT NULL AND lower(\"Name\") LIKE'%{wildcard}%' " +
                           $"OR \"StatId\" IS NOT NULL AND lower(\"StatId\") LIKE'%{wildcard}%' " +
                           $"OR \"TaxRegId\" IS NOT NULL AND lower(\"TaxRegId\") LIKE'%{wildcard}%' " +
                           $"OR \"ExternalId\" IS NOT NULL AND lower(\"ExternalId\") LIKE'%{wildcard}%' " +
                           "OR \"AddressId\" IS NOT NULL AND " +
                           $"(\"Address_part1\" IS NOT NULL AND lower(\"Address_part1\") LIKE'%{wildcard}%' " +
                           $"OR \"Address_part2\" IS NOT NULL AND lower(\"Address_part2\") LIKE'%{wildcard}%' " +
                           $"OR \"Address_part3\" IS NOT NULL AND lower(\"Address_part3\") LIKE'%{wildcard}%'))");
            }

            if (query.Type.HasValue)
            {
                filtered = filtered.Where(x => x.UnitType == query.Type.Value);
                if (query.Type.Value != StatUnitTypes.EnterpriseGroup)
                    filter.Add($"\"Discriminator\" = '{query.Type.Value}' ");
            }

            if (query.TurnoverFrom.HasValue)
            {
                filtered = filtered.Where(x => x.Turnover >= query.TurnoverFrom);
                filter.Add($"\"Turnover\" >= {query.TurnoverFrom} ");
            }

            if (query.TurnoverTo.HasValue)
            {
                filtered = filtered.Where(x => x.Turnover <= query.TurnoverTo);
                filter.Add($"\"Turnover\" <= {query.TurnoverTo} ");
            }

            if (query.EmployeesNumberFrom.HasValue)
            {
                filtered = filtered.Where(x => x.Employees >= query.EmployeesNumberFrom);
                filter.Add($"\"Employees\" >= {query.EmployeesNumberFrom} ");
            }

            if (query.EmployeesNumberTo.HasValue)
            {
                filtered = filtered.Where(x => x.Employees <= query.EmployeesNumberTo);
                filter.Add($"\"Employees\" <= {query.EmployeesNumberTo} ");
            }

            if (query.SectorCodeId.HasValue)
            {
                filtered = filtered.Where(x => x.SectorCodeId == query.SectorCodeId);
                filter.Add($"\"InstSectorCodeId\" = {query.SectorCodeId} ");
            }

            if (query.LegalFormId.HasValue)
            {
                filtered = filtered.Where(x => x.LegalFormId == query.LegalFormId);
                filter.Add($"\"LegalFormId\" = {query.LegalFormId} ");
            }

            if (query.RegMainActivityId.HasValue)
            {
                var activitiesId = await _readCtx.Activities.Where(x => x.ActivityRevx == query.RegMainActivityId).Select(x => x.Id)
                    .ToListAsync();
                var statUnitsIds = await _dbContext.ActivityStatisticalUnits.Where(x => activitiesId.Contains(x.ActivityId))
                    .Select(x => x.UnitId).ToListAsync();
                filtered = filtered.Where(x => statUnitsIds.Contains(x.RegId));
                activities = "left join public.\"ActivityStatisticalUnits\" on \"Unit_Id\" = \"RegId\" left join public.\"Activities\" on \"Activity_Id\" = \"Id\"";
                filter.Add($"\"Activity_Revx\" = {query.RegMainActivityId} ");
            }

            if (query.LastChangeFrom.HasValue)
            {
                filtered = filtered.Where(x => x.StartPeriod >= query.LastChangeFrom);
                filter.Add($"\"StartPeriod\" >= '{query.LastChangeFrom}' ");
            }

            if (query.LastChangeTo.HasValue)
            {
                filtered = filtered.Where(x => x.StartPeriod <= query.LastChangeTo);
                filter.Add($"\"StartPeriod\" <= '{query.LastChangeTo}' ");
            }

            if (!string.IsNullOrEmpty(query.DataSource))
            {
                filtered = filtered.Where(x => x.DataSource != null && x.DataSource.ToLower().Contains(query.DataSource.ToLower()));
                filter.Add($"(\"DataSource\" IS NOT NULL AND lower(\"DataSource\") LIKE'%{query.LastChangeTo}%') ");
            }

            if (!string.IsNullOrEmpty(query.RegionCode))
            {
                var regionId = _dbContext.Regions.FirstOrDefault(x => x.Code == query.RegionCode).Id;
                filtered = filtered.Where(x => x.Address != null && x.Address.RegionId == regionId);
                filter.Add($"\"Region_id\" = {regionId}");
            }

            var total = GetFilteredTotalCount(filter, query.Type, activities);
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            var result = await filtered
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToListAsync();

            return SearchVm.Create(result, total);
        }

        private int GetFilteredTotalCount(IReadOnlyCollection<string> filter, StatUnitTypes? statUnitType, string activities = null)
        {
            var connection = _dbContext.Database.GetDbConnection();
            if (connection.State != ConnectionState.Open) connection.Open();

            var commandText = "";
            var enterprise = 
                "select count(*) from public.\"EnterpriseGroups\" left join public.\"Address\" on \"Address_id\" = \"AddressId\" where {where}";

            var statUnits =
                "select count(*) from public.\"StatisticalUnits\" left join public.\"Address\" on \"Address_id\" = \"AddressId\" {activities} where {where}";

            if (!statUnitType.HasValue && string.IsNullOrEmpty(activities))
                commandText = $"select (({statUnits}) + ({enterprise}))";
            else if (statUnitType == StatUnitTypes.EnterpriseGroup)
                commandText = enterprise;
            else
                commandText = statUnits;

            using (var command = connection.CreateCommand())
            {
                commandText = commandText.Replace("{where}", filter.Count != 0
                    ? string.Join(" AND ", filter)
                    : "1=1");
                commandText = commandText.Replace("{activities}", string.IsNullOrEmpty(activities) ? " " : activities);
                command.CommandText = commandText;
                return Convert.ToInt32(command.ExecuteScalar().ToString());
            }
            
        }

        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.StatId != null
                    && unit.StatId.StartsWith(code, StringComparison.OrdinalIgnoreCase)
                    && unit.ParentId == null
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }

        public async Task<List<UnitLookupVm>> SearchByName(string wildcard, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.Name != null
                    && unit.Name.StartsWith(wildcard, StringComparison.OrdinalIgnoreCase)
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }
    }
}
