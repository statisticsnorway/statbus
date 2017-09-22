using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.SampleFrame;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис поиска
    /// </summary>
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

        /// <summary>
        /// Метод поиска стат. единицы
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="deletedOnly">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);

            var statUnitPredicate = PredicateBuilder.GetPredicate<StatisticalUnit>(query.TurnoverFrom, query.TurnoverTo,
                query.EmployeesNumberFrom, query.EmployeesNumberTo, query.Comparison);
            var entGroupPredicate = PredicateBuilder.GetPredicate<EnterpriseGroup>(query.TurnoverFrom, query.TurnoverTo,
                query.EmployeesNumberFrom, query.EmployeesNumberTo, query.Comparison);
            var unit = _readCtx.LocalUnits
                .Where(x => x.ParentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Where(statUnitPredicate)
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
                .Where(statUnitPredicate)
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
                .Where(statUnitPredicate)
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
                .Where(entGroupPredicate)
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
                activities = "left join \"ActivityStatisticalUnits\" on \"Unit_Id\" = \"RegId\" left join \"Activities\" on \"Activity_Id\" = \"Id\"";
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

        /// <summary>
        /// Метод получения фильтрации от общего количества
        /// </summary>
        /// <param name="filter">Фильт</param>
        /// <param name="statUnitType">Тип стат. единицы</param>
        /// <param name="activities">Деятельности</param>
        /// <returns></returns>
        private int GetFilteredTotalCount(IReadOnlyCollection<string> filter, StatUnitTypes? statUnitType, string activities = null)
        {
            var connection = _dbContext.Database.GetDbConnection();
            if (connection.State != ConnectionState.Open) connection.Open();

            var commandText = "";
            var enterprise = 
                "select count(*) from \"EnterpriseGroups\" left join \"Address\" on \"Address_id\" = \"AddressId\" where {where}";

            var statUnits =
                "select count(*) from \"StatisticalUnits\" left join \"Address\" on \"Address_id\" = \"AddressId\" {activities} where {where}";

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

        /// <summary>
        /// Метод поиска стат. единицы по коду
        /// </summary>
        /// <param name="code">Код</param>
        /// <param name="limit">Ограничение отображаемости</param>
        /// <returns></returns>
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

        /// <summary>
        /// Метод поиска стат. единицы по имени
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <param name="limit">Ограничение отображаемости</param>
        /// <returns></returns>
        public async Task<List<UnitLookupVm>> SearchByName(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.Name != null
                    && unit.Name.ToLower().Contains(loweredwc)
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).GroupBy(s => s.StatId).Select(g => g.First()).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).GroupBy(s=> s.StatId).Select(g => g.First()).Select(Common.UnitMapping);
            var list = await units.Concat(eg).OrderBy(o => o.Item1.Name).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }
    }
}
