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
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Search service
    /// </summary>
    public class LookupService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly IMapper _mapper;

        public LookupService(NSCRegDbContext dbContext, IMapper mapper)
        {
            _dbContext = dbContext;
            _mapper = mapper;
        }

        /// <summary>
        /// Method to get the search object
        /// </summary>
        /// <param name = "lookup"> of the search object </param>
        /// <returns> </returns>
        public async Task<IEnumerable<CodeLookupVm>> GetLookupByEnum(LookupEnum lookup)
        {
            IQueryable<object> query;
            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _dbContext.LocalUnits.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _dbContext.LegalUnits.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _dbContext.EnterpriseUnits.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _dbContext.EnterpriseGroups.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.CountryLookup:
                    query = _dbContext.Countries.OrderBy(x => x.Name)
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"({x.IsoCode}) ({x.Code}) {x.Name}", NameLanguage1 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage1}", NameLanguage2 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage2}" });
                    break;
                case LookupEnum.LegalFormLookup:
                    query = _dbContext.LegalForms.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _dbContext.SectorCodes.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.PersonTypeLookup:
                    query = _dbContext.PersonTypes.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.UnitStatusLookup:
                    query = _dbContext.UnitStatuses.Where(x => !x.IsDeleted).Select(x => new CodeLookupVm  { Id = x.Id, Name = x.Name });
                    break;
                case LookupEnum.ForeignParticipationLookup:
                    query = _dbContext.ForeignParticipations.Where(x => !x.IsDeleted).Select(x => new CodeLookupVm { Id = x.Id, Name = x.Name });
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        /// <summary>
        /// Method for obtaining object search pagination
        /// </summary>
        /// <param name = "lookup"> of the search object </param>
        /// <param name = "searchModel"> search model </param>
        /// <returns> </returns>
        public async Task<IEnumerable<CodeLookupVm>> GetPaginateLookupByEnum(LookupEnum lookup, SearchLookupModel searchModel)
        {
            IQueryable<object> query;
            Expression<Func<IStatisticalUnit, bool>> searchCriteia;
            Expression<Func<CodeLookupBase, bool>> searchCodeLookupCriteia;
            Expression<Func<Country, bool>> searchIsoCodeLookupCriteia;
            var loweredWc = searchModel.Wildcard?.ToLower();
            var statIdSearch = false;

            if (string.IsNullOrEmpty(searchModel.Wildcard))
            {
                searchCriteia = x => !x.IsDeleted;
                searchCodeLookupCriteia = x => !x.IsDeleted;
                searchIsoCodeLookupCriteia = x => !x.IsDeleted;
            }
            else
            {
               

                searchCriteia = x => !x.IsDeleted &&
                                     (!statIdSearch && x.Name.ToLower().Contains(loweredWc)
                                     || statIdSearch && x.StatId == loweredWc);

                searchCodeLookupCriteia = x => !x.IsDeleted
                                               && x.Name.ToLower().Contains(loweredWc)
                                               || x.NameLanguage1.ToLower().Contains(loweredWc)
                                               || x.NameLanguage2.ToLower().Contains(loweredWc)
                                               || x.Code.ToLower().StartsWith(loweredWc);

                searchIsoCodeLookupCriteia = x => !x.IsDeleted
                                               && x.Name.ToLower().Contains(loweredWc)
                                               || x.NameLanguage1.ToLower().Contains(loweredWc)
                                               || x.NameLanguage2.ToLower().Contains(loweredWc)
                                               || x.IsoCode.ToLower().StartsWith(loweredWc)
                                               || x.Code.ToLower().StartsWith(loweredWc);
            }

            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    statIdSearch = await StatUnitExistsByStatId<LocalUnit>(loweredWc);
                    query = _dbContext.LocalUnits.Where(searchCriteia);
                    break;
                case LookupEnum.LegalUnitLookup:
                    statIdSearch = await StatUnitExistsByStatId<LegalUnit>(loweredWc);
                    query = _dbContext.LegalUnits.Where(searchCriteia);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    statIdSearch = await StatUnitExistsByStatId<EnterpriseUnit>(loweredWc);
                    query = _dbContext.EnterpriseUnits.Where(searchCriteia)
                        .Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    statIdSearch = await StatUnitExistsByStatId<EnterpriseGroup>(loweredWc);
                    query = _dbContext.EnterpriseGroups.Where(searchCriteia);
                    break;
                case LookupEnum.CountryLookup:
                    return (await _dbContext.Countries
                            .Where(searchIsoCodeLookupCriteia)
                            .OrderBy(x => x.Name)
                            .ToListAsync())
                        .Select(x => new CodeLookupVm {
                            Id = x.Id,
                            Name = $"({x.IsoCode}) ({x.Code}) {x.Name}",
                            NameLanguage1 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage1}",
                            NameLanguage2 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage2}"
                        });

                case LookupEnum.LegalFormLookup:
                    query = _dbContext.LegalForms.Where(searchCodeLookupCriteia);
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _dbContext.SectorCodes.Where(searchCodeLookupCriteia);
                    break;
                case LookupEnum.DataSourceClassificationLookup:
                    query = _dbContext.DataSourceClassifications.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.ReorgTypeLookup:
                    query = _dbContext.ReorgTypes.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.EntGroupTypeLookup:
                    query = _dbContext.EnterpriseGroupTypes.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.UnitStatusLookup:
                    query = _dbContext.UnitStatuses.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.UnitSizeLookup:
                    query = _dbContext.UnitSizes.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.ForeignParticipationLookup:
                    query = _dbContext.ForeignParticipations.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.RegistrationReasonLookup:
                    query = _dbContext.RegistrationReasons.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.PersonTypeLookup:
                    query = _dbContext.PersonTypes.Where(x => !x.IsDeleted)
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name}", NameLanguage1 = $"{x.NameLanguage1}", NameLanguage2 = $"{x.NameLanguage2}" });
                    break;
                case LookupEnum.RegionLookup:
                    return (await _dbContext.Regions
                            .Where(searchCodeLookupCriteia)
                            .OrderBy(x => x.Code)
                            .Skip(searchModel.Page * searchModel.PageSize)
                            .Take(searchModel.PageSize)
                            .ToListAsync())
                        .Select(region => new CodeLookupVm
                        {
                            Id = region.Id,
                            Name = $"{region.Code} {(region as Region)?.FullPath ?? region.Name}",
                            NameLanguage1 = $"{region.Code} {(region as Region)?.FullPathLanguage1 ?? region.NameLanguage1}",
                            NameLanguage2 = $"{region.Code} {(region as Region)?.FullPathLanguage2 ?? region.NameLanguage2}"
                        });
                case LookupEnum.ActivityCategoryLookup:
                    return (await _dbContext.ActivityCategories
                            .Where(searchCodeLookupCriteia)
                            .OrderBy(x => x.Code)
                            .Skip(searchModel.Page * searchModel.PageSize)
                            .Take(searchModel.PageSize)
                            .ToListAsync())
                        .Select(act => new CodeLookupVm
                        {
                            Id = act.Id,
                            Name = act.Name,
                            Code = act.Code,
                            NameLanguage1 = act.NameLanguage1,
                            NameLanguage2 = act.NameLanguage2
                        });
                case LookupEnum.EntGroupRoleLookup:
                    query = _dbContext.EnterpriseGroupRoles.Where(x => !x.IsDeleted);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            query = query.Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
            return await Execute(query);
        }

        private async Task<bool> StatUnitExistsByStatId<T>(string statId) where T: class, IStatisticalUnit
        {
            return await _dbContext.Set<T>().AnyAsync(x => x.StatId == statId);
        }

        /// <summary>
        /// Method of obtaining a search object by Id
        /// </summary>
        /// <param name = "lookup"> of the search object </param>
        /// <param name = "ids"> id </param>
        /// <param name = "showDeleted"> Distance flag </param>
        /// <returns> </returns>
        public virtual async Task<IEnumerable<CodeLookupVm>> GetById(LookupEnum lookup, int[] ids)
        {
            IQueryable<object> query;

            Expression<Func<IStatisticalUnit, bool>> statUnitSearchCriteia = v => ids.Contains(v.RegId) && !v.IsDeleted;

            Expression<Func<LookupBase, bool>> lookupSearchCriteia = v => ids.Contains(v.Id) && !v.IsDeleted;

            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _dbContext.LocalUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _dbContext.LegalUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _dbContext.EnterpriseUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _dbContext.EnterpriseGroups.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.CountryLookup:
                    return (await GetAllCountryLookUps(ids));
                case LookupEnum.LegalFormLookup:
                    query = _dbContext.LegalForms.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _dbContext.SectorCodes.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.DataSourceClassificationLookup:
                    query = _dbContext.DataSourceClassifications.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.ReorgTypeLookup:
                    query = _dbContext.ReorgTypes.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.EntGroupTypeLookup:
                    query = _dbContext.EnterpriseGroupTypes.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.UnitStatusLookup:
                    query = _dbContext.UnitStatuses.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.UnitSizeLookup:
                    query = _dbContext.UnitSizes.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.ForeignParticipationLookup:
                    query = _dbContext.ForeignParticipations.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.RegistrationReasonLookup:
                    query = _dbContext.RegistrationReasons.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.PersonTypeLookup:
                    query = _dbContext.PersonTypes.Where(lookupSearchCriteia)
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name}", NameLanguage1 = $"{x.NameLanguage1}", NameLanguage2 = $"{x.NameLanguage2}" });
                    break;
                case LookupEnum.RegionLookup:
                    return (await GetAllRegionLookUps(ids));
                case LookupEnum.ActivityCategoryLookup:
                    return (await GetAllActivityCategoryLookUps(ids));
                case LookupEnum.EntGroupRoleLookup:
                    query = _dbContext.EnterpriseGroupRoles.Where(lookupSearchCriteia);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        /// <summary>
        /// Method for performing search queries
        /// </summary>
        /// <param name = "query"> </param>
        /// <returns> </returns>
        private async Task<IEnumerable<CodeLookupVm>> Execute(IQueryable<object> query)
        {
            var model = await query.ToListAsync();
            return _mapper.Map<IEnumerable<CodeLookupVm>>(model);
        }

        private async Task<List<CodeLookupVm>> GetAllCountryLookUps(int[] ids)
        {
            var country = await _dbContext.Countries
                .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                .OrderBy(x => x.Name)
                .Select(x => new CodeLookupVm
                {
                    Id = x.Id,
                    Name = $"({x.IsoCode}) ({x.Code}) {x.Name}",
                    NameLanguage1 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage1}",
                    NameLanguage2 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage2}"
                }).ToListAsync();
            return country;
        }

        private async Task<List<CodeLookupVm>> GetAllRegionLookUps(int[] ids)
        {
            var regions = await _dbContext.Regions
                .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                .OrderBy(x => x.Code)
                .Select(x => new CodeLookupVm
                {
                    Id = x.Id,
                    Name = $"{x.Code} {x.FullPath ?? x.Name}",
                    NameLanguage1 = $"{x.Code} {x.FullPathLanguage1 ?? x.NameLanguage1}",
                    NameLanguage2 = $"{x.Code} {x.FullPathLanguage1 ?? x.NameLanguage2}"
                })
                .ToListAsync();
            return regions;
        }

        private async Task<List<CodeLookupVm>> GetAllActivityCategoryLookUps(int[] ids)
        {
            var activitys = await _dbContext.ActivityCategories
                .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                .OrderBy(x => x.Code)
                .Select(x => new CodeLookupVm
                {
                    Id = x.Id,
                    Code = x.Code,
                    Name = x.Name,
                    NameLanguage1 = x.NameLanguage1,
                    NameLanguage2 = x.NameLanguage2
                }).ToListAsync();
            return activitys;
        }
    }
}
