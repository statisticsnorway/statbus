using System;
using System.Collections.Generic;
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
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class SearchService
    {
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;

        public SearchService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
            _userService = new UserService(dbContext);
        }

        
        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);
            var unit = _readCtx.LocalUnits
                .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                .Include(x => x.Address)
                .ThenInclude(x => x.Region)
                .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                .Select(
                    x =>
                        new SearchingItem(x)
                        {
                           RegId = x.RegId,
                           Name = x.Name,
                           StatId = x.StatId,
                           TaxRegId = x.TaxRegId,
                           ExternalId = x.ExternalId,
                           Address = x.Address,
                           Turnover = x.Turnover,
                           Employees = x.Employees,
                           RegMainActivityId = x.RegMainActivityId,
                           SectorCodeId = (int?)null,
                           LegalFormId = (int?)null,
                           DataSource = x.DataSource,
                           StartPeriod = x.StartPeriod,
                           UnitType = StatUnitTypes.LocalUnit
                        });
            var legalUnit = _readCtx.LegalUnits
                        .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                        .Include(x => x.Address)
                        .ThenInclude(x => x.Region)
                        .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                        .Select(
                            x =>
                                new SearchingItem(x)
                                {
                                    RegId = x.RegId,
                                    Name = x.Name,
                                    StatId = x.StatId,
                                    TaxRegId = x.TaxRegId,
                                    ExternalId = x.ExternalId,
                                    Address = x.Address,
                                    Turnover = x.Turnover,
                                    Employees = x.Employees,
                                    RegMainActivityId = x.RegMainActivityId,
                                    SectorCodeId = x.InstSectorCodeId,
                                    LegalFormId = x.LegalFormId,
                                    DataSource = x.DataSource,
                                    StartPeriod = x.StartPeriod,
                                    UnitType = StatUnitTypes.LegalUnit
                                });
            var enterpriseUnit = _readCtx.EnterpriseUnits
                            .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                            .Include(x => x.Address)
                            .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                            .Select(
                                x =>
                                    new SearchingItem(x)
                                    {
                                        RegId = x.RegId,
                                        Name = x.Name,
                                        StatId = x.StatId,
                                        TaxRegId = x.TaxRegId,
                                        ExternalId = x.ExternalId,
                                        Address = x.Address,
                                        Turnover = x.Turnover,
                                        Employees = x.Employees,
                                        RegMainActivityId = x.RegMainActivityId,
                                        SectorCodeId = x.InstSectorCodeId,
                                        LegalFormId = (int?)null,
                                        DataSource = x.DataSource,
                                        StartPeriod = x.StartPeriod,
                                        UnitType = StatUnitTypes.EnterpriseUnit
                                    });
            var group = _readCtx.EnterpriseGroups
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new SearchingItem(x)
                            {

                                RegId = x.RegId,
                                Name = x.Name,
                                StatId = x.StatId,
                                TaxRegId = x.TaxRegId,
                                ExternalId = x.ExternalId,
                                Address = x.Address,
                                Turnover = x.Turnover,
                                Employees = x.Employees,
                                RegMainActivityId = null as int?,
                                SectorCodeId = null as int?,
                                LegalFormId = null as int?,
                                DataSource = x.DataSource,
                                StartPeriod = x.StartPeriod,
                                UnitType = StatUnitTypes.EnterpriseGroup,
                            });

            var filtered = unit.Concat(group).Concat(legalUnit).Concat(enterpriseUnit);

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.ToLower().Contains(query.Wildcard.ToLower());
                filtered = filtered.Where(x =>
                    x.Name.ToLower().Contains(query.Wildcard.ToLower())
                    || checkWildcard(x.StatId)
                    || checkWildcard(x.TaxRegId)
                    || checkWildcard(x.ExternalId)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)));
            }

            if (query.Type.HasValue)
                filtered = filtered.Where(x => x.UnitType == query.Type.Value);

            if (query.TurnoverFrom.HasValue)
                filtered = filtered.Where(x => x.Turnover >= query.TurnoverFrom);

            if (query.TurnoverTo.HasValue)
                filtered = filtered.Where(x => x.Turnover <= query.TurnoverTo);

            if (query.EmployeesNumberFrom.HasValue)
                filtered = filtered.Where(x => x.Employees >= query.EmployeesNumberFrom);

            if (query.EmployeesNumberTo.HasValue)
                filtered = filtered.Where(x => x.Employees <= query.EmployeesNumberTo);

            if (query.SectorCodeId.HasValue)
                filtered = filtered.Where(x => x.SectorCodeId.HasValue && x.SectorCodeId == query.SectorCodeId);

            if (query.LegalFormId.HasValue)
                filtered = filtered.Where(x => x.LegalFormId.HasValue && x.LegalFormId == query.LegalFormId);

            if (query.RegMainActivityId.HasValue)
                filtered = filtered.Where(x => x.RegMainActivityId.HasValue && x.RegMainActivityId == query.RegMainActivityId);

            if (query.LastChangeFrom.HasValue)
                filtered = filtered.Where(x => x.StartPeriod >= query.LastChangeFrom);

            if (query.LastChangeTo.HasValue)
                filtered = filtered.Where(x => x.StartPeriod <= query.LastChangeTo);

            if (!string.IsNullOrEmpty(query.DataSource))
                filtered = filtered.Where(x => x.DataSource != null && x.DataSource.ToLower().Contains(query.DataSource.ToLower()));

            if (!string.IsNullOrEmpty(query.RegionCode))
                filtered = filtered.Where(x => x.Region != null && x.Region.Code == query.RegionCode);

            var total = filtered.Count();
            var take = query.PageSize;
            var skip = query.PageSize * (query.Page - 1);

            var result = filtered
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToList();

            return SearchVm.Create(result, total);
        }

        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit =>
                    unit.StatId != null
                    && unit.StatId.StartsWith(code, StringComparison.OrdinalIgnoreCase)
                    && unit.ParrentId == null
                    && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(Common.UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(Common.UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return Common.ToUnitLookupVm(list).ToList();
        }
    }

    class SearchingItem
    {
        public SearchingItem(IStatisticalUnit unit) => Region = unit.Address?.Region;

        public int RegId { get; set; }
        public string Name { get; set; }
        public string StatId { get; set; }
        public int Employees { get; set; }
        public int? RegMainActivityId { get; set; }
        public int? SectorCodeId { get; set; }
        public int? LegalFormId { get; set; }
        public string TaxRegId { get; set; }
        public string ExternalId { get; set; }
        public Address Address { get; set; }
        public Region Region { get; set; }
        public decimal Turnover { get; set; }
        public StatUnitTypes UnitType { get; set; }
        public DateTime StartPeriod { get; set; }
        public string DataSource { get; set; }
    }

}
