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
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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

            if (string.IsNullOrEmpty(searchModel.Wildcard))
            {
                searchCriteia = x => !x.IsDeleted && x.ParentId == null;
                searchCodeLookupCriteia = x => !x.IsDeleted;
            }
            else
            {
                var loweredWc = searchModel.Wildcard.ToLower();

                searchCriteia = x => !x.IsDeleted && x.ParentId == null && !string.IsNullOrEmpty(x.Name) &&
                                     x.Name.ToLower().Contains(loweredWc);

                searchCodeLookupCriteia = x => !x.IsDeleted
                                               && x.Name.ToLower().Contains(loweredWc)
                                               || x.Code.ToLower().Contains(loweredWc);
            }

            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _dbContext.LocalUnits.Where(searchCriteia);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _dbContext.LegalUnits.Where(searchCriteia);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _dbContext.EnterpriseUnits.Where(searchCriteia)
                        .Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _dbContext.EnterpriseGroups.Where(searchCriteia);
                    break;
                case LookupEnum.CountryLookup:
                    return (await _dbContext.Countries
                            .Where(searchCodeLookupCriteia)
                            .OrderBy(x => x.Name)
                            .Skip(searchModel.Page * searchModel.PageSize)
                            .Take(searchModel.PageSize)
                            .ToListAsync())
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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
                case LookupEnum.RegionLookup:
                    return (await _dbContext.Regions
                            .Where(searchCodeLookupCriteia)
                            .OrderBy(x => x.Code)
                            .Skip(searchModel.Page * searchModel.PageSize)
                            .Take(searchModel.PageSize)
                            .ToListAsync())
                        .Select(region => new CodeLookupVm { Id = region.Id, Name = $"({region.Code}) {region.Name}" });
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            query = query.Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
            return await Execute(query);
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
                        .Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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
                case LookupEnum.RegionLookup:
                    return (await _dbContext.Regions
                            .Where(x => !x.IsDeleted && ids.Contains(x.Id))
                            .OrderBy(x => x.Code)
                            .ToListAsync())
                        .Select(region => new CodeLookupVm {Id = region.Id, Name = $"({region.Code}) {region.Name}"});
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
