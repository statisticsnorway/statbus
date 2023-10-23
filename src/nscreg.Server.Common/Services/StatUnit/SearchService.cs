using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.StatUnits.Search;
using nscreg.Utilities.Extensions;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Class search service
    /// </summary>
    public class SearchService
    {
        private readonly IUserService _userService;
        private readonly NSCRegDbContext _dbContext;
        private readonly IElasticUpsertService _elasticService;
        private readonly CommonService _commonSvc;
        private readonly LinkService _linkService;
        private readonly IMapper _mapper;

        public SearchService(IUserService userService, IElasticUpsertService elasticService, CommonService commonSvc,
            LinkService linkService, NSCRegDbContext dbContext, IMapper mapper)
        {
            _userService = userService;
            _dbContext = dbContext;
            _elasticService = elasticService;
            _commonSvc = commonSvc;
            _linkService = linkService;
            _mapper = mapper;
        }

        /// <summary>
        /// Stat search method. units
        /// </summary>
        /// <param name = "filter"> Request </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "isDeleted"> Distance flag </param>
        /// <returns> </returns>
        public async Task<SearchVm> Search(SearchQueryM filter, string userId, bool isDeleted = false)
        {
            await _elasticService.CheckElasticSearchConnection();
            bool isAdmin = await _userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator);

            long totalCount;
            List<ElasticStatUnit> units;
            if (filter.IsEmpty())
            {
                var baseQuery = _dbContext.StatUnitSearchView
                    .Where(s => s.IsDeleted == isDeleted && s.LiqDate == null)
                    // How the most recent entries at the top.
                    // And get predictable ordering for the pagination below.
                    .OrderByDescending(s => s.StatId);

                totalCount = baseQuery.Count();
                var dbUnits = await baseQuery.Skip((filter.Page - 1) * filter.PageSize).Take(filter.PageSize)
                    .ToListAsync();
                units = dbUnits.Select(_mapper.Map<StatUnitSearchView, ElasticStatUnit>).ToList();
            }
            else
            {
                var searchResponse = await _elasticService.Search(filter, userId, isDeleted);
                totalCount = searchResponse.TotalCount;
                units = searchResponse.Result.ToList();
            }

            var finalIds = units.Where(x => x.UnitType != StatUnitTypes.EnterpriseGroup)
                .Select(x => x.RegId).ToList();
            var finalRegionIds = units.Select(x => x.ActualAddressRegionId).ToList();

            var unitsToPersonNames = await GetUnitsToPersonNamesByUnitIds(finalIds);

            var unitsToMainActivities = await GetUnitsToPrimaryActivities(finalIds);

            var regions = await GetRegionsFullPaths(finalRegionIds);

            var permissions = await _userService.GetDataAccessAttributes(userId, null);
            var helper = new StatUnitCheckPermissionsHelper(_dbContext);
            var result = units
                .Select(x => new SearchViewAdapterModel(x, unitsToPersonNames[x.RegId],
                    unitsToMainActivities[x.RegId],
                    regions.GetValueOrDefault(x.ActualAddressRegionId ?? x.ActualAddressRegionId), _mapper))
                .Select(x => SearchItemVm.Create(x, x.UnitType,
                    permissions.GetReadablePropNames(), !isAdmin &&
                    !helper.IsRegionOrActivityContains(userId, x.ActualAddressRegionId != null ? new List<int> { (int)x.ActualAddressRegionId } : new List<int>(), unitsToMainActivities[x.RegId].Select(z => z.Id).ToList())));

            var viewModel = SearchVm.Create(result, totalCount);
            return viewModel;
        }

        private async Task<IDictionary<int?, RegionLookupVm>> GetRegionsFullPaths(ICollection<int?> finalRegionIds)
        {
            var regionIds = finalRegionIds.Where(x => x.HasValue).Select(x => x.Value).ToList();
            var regionPaths = await _dbContext.Regions.Where(x => regionIds.Contains(x.Id))
                .Select(x => new {x.Id, x.FullPath, x.FullPathLanguage1, x.FullPathLanguage2}).ToListAsync();
            return regionPaths
                .ToDictionary(x => (int?) x.Id, x => new RegionLookupVm
                {
                    FullPath = x.FullPath,
                    FullPathLanguage1 = x.FullPathLanguage1,
                    FullPathLanguage2 = x.FullPathLanguage2
                });
        }

        private async Task<ILookup<int, CodeLookupVm>> GetUnitsToPrimaryActivities(ICollection<int> regIds)
        {
            var unitsActivities = await _dbContext.ActivityStatisticalUnits
                .Where(x => regIds.Contains(x.UnitId) && x.Activity.ActivityType == ActivityTypes.Primary)
                .Select(x =>
                new {
                    x.UnitId,
                    x.Activity.ActivityCategory.Code,
                    x.Activity.ActivityCategory.Name,
                    x.Activity.ActivityCategory.NameLanguage1,
                    x.Activity.ActivityCategory.NameLanguage2,
                    x.Activity.ActivityCategoryId
                })
                .ToListAsync();

            return unitsActivities
                .ToLookup(x => x.UnitId, x => new CodeLookupVm()
                {
                    Id  = x.ActivityCategoryId,
                    Code = x.Code,
                    Name = $"{x.Code} {x.Name}",
                    NameLanguage1 = $"{x.Code} {x.NameLanguage1}",
                    NameLanguage2 = $"{x.Code} {x.NameLanguage2}"
                });
        }

        private async Task<ILookup<int, string>> GetUnitsToPersonNamesByUnitIds(ICollection<int> regIds)
        {
            var personNames = await _dbContext.PersonStatisticalUnits
                .Where(x => regIds.Contains(x.UnitId))
                .Select(x => new {x.UnitId, Name = x.Person.GivenName ?? x.EnterpriseGroup.Name ?? x.Unit.Name })
                .ToListAsync();
            return personNames.ToLookup(x => x.UnitId, x => x.Name);
        }

        /// <summary>
        /// Stat search method. units by code
        /// </summary>
        /// <param name = "type"> Type of static unit </param>
        /// <param name = "code"> Code </param>
        /// <param name = "isDeleted"> Delete flag </param>
        /// <param name = "limit"> Display limitation </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "regId"> Registration Id </param>
        /// <param name = "page"> Current page </param>
        /// <returns> </returns>
        public async Task<List<UnitLookupVm>> Search(StatUnitTypes type, string code, string userId, int regId,  bool isDeleted, int limit = 5, int page = 1)
        {
            if (isDeleted)
            {
                var list = new List<UnitLookupVm>();

                var root = new UnitSubmitM()
                {
                    Id = regId,
                    Type = type
                };
                switch (type)
                {
                    case StatUnitTypes.EnterpriseGroup:
                        list.AddRange(_commonSvc.ToUnitLookupVm(
                            await _commonSvc.GetUnitsList<EnterpriseUnit>(false)
                                .Where(v => v.EntGroupId == regId)
                                .Select(CommonService.UnitMapping)
                                .ToListAsync()
                        ));
                            break;
                    case StatUnitTypes.EnterpriseUnit:
                        list.AddRange(_commonSvc.ToUnitLookupVm(
                            await _commonSvc.GetUnitsList<EnterpriseUnit>(false)
                                .Where(v => v.RegId == regId)
                                .Include(v => v.EnterpriseGroup)
                                .Select(v => v.EnterpriseGroup)
                                .Select(CommonService.UnitMapping)
                                .ToListAsync()
                        ));
                        list.AddRange(_commonSvc.ToUnitLookupVm(
                            await _commonSvc.GetUnitsList<LegalUnit>(false)
                                .Where(v => v.EnterpriseUnitRegId == regId)
                                .Select(CommonService.UnitMapping)
                                .ToListAsync()
                        ));
                        break;
                    case StatUnitTypes.LegalUnit:
                        list.AddRange(_commonSvc.ToUnitLookupVm(
                            await _commonSvc.GetUnitsList<LegalUnit>(false)
                                .Where(v => v.RegId == regId)
                                .Include(v => v.EnterpriseUnit)
                                .Select(v => v.EnterpriseUnit)
                                .Select(CommonService.UnitMapping)
                                .ToListAsync()
                        ));
                        list.AddRange(_commonSvc.ToUnitLookupVm(
                            await _commonSvc.GetUnitsList<LocalUnit>(false)
                                .Where(v => v.LegalUnitId == regId)
                                .Select(CommonService.UnitMapping)
                                .ToListAsync()
                        ));
                        break;
                    case StatUnitTypes.LocalUnit:
                        var linkedList =  await _linkService.LinksList(root);
                        if (linkedList.Count > 0)
                        {
                            list.Add(new UnitLookupVm { Id = linkedList[0].Source1.Id, Type = linkedList[0].Source1.Type, Code = linkedList[0].Source1.Code, Name = linkedList[0].Source1.Name });
                        }
                        break;
                }

                return list;
            }

            var statUnitTypes = new List<StatUnitTypes>();
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    statUnitTypes.Add(StatUnitTypes.LegalUnit);
                    break;
                case StatUnitTypes.LegalUnit:
                    statUnitTypes.Add(StatUnitTypes.LocalUnit);
                    statUnitTypes.Add(StatUnitTypes.EnterpriseUnit);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    statUnitTypes.Add(StatUnitTypes.LegalUnit);
                    statUnitTypes.Add(StatUnitTypes.EnterpriseGroup);
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    statUnitTypes.Add(StatUnitTypes.EnterpriseUnit);
                    break;
            }

            var filter = new SearchQueryM
            {
                Type = statUnitTypes,
                StatId = code,
                Page = page,
                PageSize = limit
            };

            var searchResponse = await _elasticService.Search(filter, userId, isDeleted);
            return searchResponse.Result.Select(u => new UnitLookupVm { Id = u.RegId, Code = u.StatId, Name = u.Name, Type = u.UnitType}).ToList();
            }

        /// <summary>
        /// Stat search method. units by name
        /// </summary>
        /// <param name = "wildcard"> Search template </param>
        /// <param name = "limit"> Display limitation </param>
        /// <returns> </returns>
        public async Task<List<UnitLookupVm>> SearchByWildcard(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            Expression<Func<IStatisticalUnit, bool>> filter =
                unit => !unit.IsDeleted &&
                    (unit.Name != null && unit.Name.ToLower().Contains(loweredwc) || unit.StatId.StartsWith(loweredwc));
            var units = _dbContext.StatisticalUnits.Where(filter).GroupBy(s => s.StatId).Select(g => g.First())
                .Select(CommonService.UnitMapping);
            var eg = _dbContext.EnterpriseGroups.Where(filter).GroupBy(s => s.StatId).Select(g => g.First())
                .Select(CommonService.UnitMapping);
            var list = await units.Concat(eg).OrderBy(o => o.Item1.Code).Take(limit).ToListAsync();
            return _commonSvc.ToUnitLookupVm(list).ToList();
        }

        /// <summary>
        /// Validates provided statId uniqueness
        /// </summary>
        /// <param name = "unitType"> </param>
        /// <param name = "statId"> </param>
        /// <param name = "unitId"> </param>
        /// <returns> </returns>
        public async Task<bool> ValidateStatIdUniquenessAsync(int? unitId, StatUnitTypes unitType, string statId)
        {
            if (unitType == StatUnitTypes.EnterpriseGroup)
            {
                return !await _dbContext.EnterpriseGroups
                    .AnyAsync(x => x.StatId == statId && x.RegId != unitId);
            }
            return !await _dbContext.StatisticalUnits
                .AnyAsync(x => x.StatId == statId && x.RegId != unitId && x.UnitType == unitType);
        }
    }
}
