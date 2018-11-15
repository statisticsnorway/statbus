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
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис поиска
    /// </summary>
    public class LookupService
    {
        private readonly NSCRegDbContext _dbContext;

        public LookupService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        /// <summary>
        /// Метод получения объекта поиска
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <returns></returns>
        public async Task<IEnumerable<CodeLookupVm>> GetLookupByEnum(LookupEnum lookup)
        {
            IQueryable<object> query;
            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _dbContext.LocalUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _dbContext.LegalUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _dbContext.EnterpriseUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _dbContext.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParentId == null);
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
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        /// <summary>
        /// Метод получения пагинации поиска объекта
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <param name="searchModel">модель поиска</param>
        /// <returns></returns>
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
                searchCriteia = x => !x.IsDeleted && x.ParentId == null;
                searchCodeLookupCriteia = x => !x.IsDeleted;
                searchIsoCodeLookupCriteia = x => !x.IsDeleted;
            }
            else
            {
               

                searchCriteia = x => !x.IsDeleted && x.ParentId == null &&
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
                case LookupEnum.UnitStatusLookup:
                    query = _dbContext.UnitStatuses.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.UnitSizeLookup:
                    query = _dbContext.UnitsSize.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.ForeignParticipationLookup:
                    query = _dbContext.ForeignParticipations.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.RegistrationReasonLookup:
                    query = _dbContext.RegistrationReasons.Where(x => !x.IsDeleted);
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
        /// Метод получения объекта поиска по Id
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <param name="ids">id</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<IEnumerable<CodeLookupVm>> GetById(LookupEnum lookup, int[] ids,
            bool showDeleted = false)
        {
            IQueryable<object> query;

            Expression<Func<IStatisticalUnit, bool>> statUnitSearchCriteia = v => ids.Contains(v.RegId) && v.IsDeleted == showDeleted;

            Expression<Func<LookupBase, bool>> lookupSearchCriteia = v => ids.Contains(v.Id) && v.IsDeleted == showDeleted;

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
                    return (await _dbContext.Countries
                        .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                        .OrderBy(x => x.Name)
                        .ToListAsync())
                        .Select(x => new CodeLookupVm
                        {
                            Id = x.Id,
                            Name = $"({x.IsoCode}) ({x.Code}) {x.Name}",
                            NameLanguage1 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage1}",
                            NameLanguage2 = $"({x.IsoCode}) ({x.Code}) {x.NameLanguage2}"
                        });
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
                case LookupEnum.UnitStatusLookup:
                    query = _dbContext.UnitStatuses.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.UnitSizeLookup:
                    query = _dbContext.UnitsSize.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.ForeignParticipationLookup:
                    query = _dbContext.ForeignParticipations.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.RegistrationReasonLookup:
                    query = _dbContext.RegistrationReasons.Where(lookupSearchCriteia);
                    break;
                case LookupEnum.RegionLookup:
                    return (await _dbContext.Regions
                            .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                            .OrderBy(x => x.Code)
                            .ToListAsync())
                        .Select(region => new CodeLookupVm { Id = region.Id,
                            Name = $"{region.Code} {region.FullPath ?? region.Name}",
                            NameLanguage1 = $"{region.Code} {region.FullPathLanguage1 ?? region.NameLanguage1}",
                            NameLanguage2 = $"{region.Code} {region.FullPathLanguage1 ?? region.NameLanguage2}"
                        });
                case LookupEnum.ActivityCategoryLookup:
                    return (await _dbContext.ActivityCategories
                            .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                            .OrderBy(x => x.Code)
                            .ToListAsync())
                        .Select(x => new CodeLookupVm
                        {
                            Id = x.Id, Code = x.Code,
                            Name = x.Name,
                            NameLanguage1 = x.NameLanguage1,
                            NameLanguage2 = x.NameLanguage2
                        });
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        /// <summary>
        /// Метод выполнения поисковых запросов
        /// </summary>
        /// <param name="query"></param>
        /// <returns></returns>
        private static async Task<IEnumerable<CodeLookupVm>> Execute(IQueryable<object> query)
            => Mapper.Map<IEnumerable<CodeLookupVm>>(await query.ToListAsync());
    }
}
