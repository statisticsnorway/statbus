using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models.StatUnits;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using nscreg.Data.Helpers;
using nscreg.Server.Models;
using nscreg.Server.Models.StatUnits.History;
using nscreg.Utilities;

namespace nscreg.Server.Services
{
    public class StatUnitService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;

        public StatUnitService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
        }

        public async Task<object> ShowHistoryAsync(StatUnitTypes type, int id)
        {
            var history = type == StatUnitTypes.EnterpriseGroup
                ? await FetchUnitHistoryAsync<EnterpriseGroup>(id)
                : await FetchUnitHistoryAsync<StatisticalUnit>(id);
            var result = history.ToArray();
            return SearchVm.Create(result, result.Length);
        }

        public async Task<object> ShowHistoryDetailsAsync(StatUnitTypes type, int id, string userId)
        {
            var history = type == StatUnitTypes.EnterpriseGroup
                ? await FetchDetailedUnitHistoryAsync<EnterpriseGroup>(id, userId)
                : await FetchDetailedUnitHistoryAsync<StatisticalUnit>(id, userId);
            var result = history.ToArray();
            return SearchVm.Create(result, result.Length);
        }

        public async Task<SearchVm<InconsistentRecord>> GetInconsistentRecordsAsync(PaginationModel model)
        {
            var validator = new InconsistentRecordValidator();
            var units =
                _dbContext.StatisticalUnits.Where(x => !x.IsDeleted && x.ParrentId == null)
                    .Select(x => validator.Specify(x))
                    .Where(x => x.Inconsistents.Count > 0);
            var groups = _dbContext.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParrentId == null)
                .Select(x => validator.Specify(x))
                .Where(x => x.Inconsistents.Count > 0);
            var records = units.Union(groups);
            var total = await records.CountAsync();
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;
            var paginatedRecords = await records.OrderBy(v => v.Type).ThenBy(v => v.Name)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToListAsync();
            return SearchVm<InconsistentRecord>.Create(paginatedRecords, total);
        }

        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId)
        {
            var item = id.HasValue
                ? await GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);
            var creator = new StatUnitViewModelCreator();
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return (StatUnitViewModel) creator.Create(item, dataAttributes);
        }

        private async Task<IEnumerable<object>> FetchUnitHistoryAsync<T>(int id)
            where T : class, IStatisticalUnit
            => await _dbContext.Set<T>()
                .Join(_dbContext.Users,
                    unit => unit.UserId,
                    user => user.Id,
                    (unit, user) => new {Unit = unit, User = user})
                .Where(x => x.Unit.ParrentId == id || x.Unit.RegId == id)
                .Select(x => new
                {
                    x.Unit.RegId,
                    x.User.Name,
                    x.Unit.ChangeReason,
                    x.Unit.EditComment,
                    x.Unit.StartPeriod,
                    x.Unit.EndPeriod
                })
                .OrderByDescending(x => x.EndPeriod)
                .ToListAsync();

        private async Task<IEnumerable<ChangedField>> FetchDetailedUnitHistoryAsync<T>(int id, string userId)
            where T : class, IStatisticalUnit
        {
            var result = await _dbContext.Set<T>()
                .Join(
                    _dbContext.Set<T>(),
                    unitAfter => unitAfter.ParrentId ?? unitAfter.RegId,
                    unitBefore => unitBefore.ParrentId,
                    (unitAfter, unitBefore) => new {UnitAfter = unitAfter, UnitBefore = unitBefore})
                .Where(x => x.UnitAfter.RegId == id && x.UnitAfter.StartPeriod == x.UnitBefore.EndPeriod)
                .FirstOrDefaultAsync();
            return result == null
                ? new List<ChangedField>()
                : await CutUnchangedFields(result.UnitAfter, result.UnitBefore, userId);
        }

        private async Task<IEnumerable<ChangedField>> CutUnchangedFields<T>(T after, T before, string userId)
            where T : class, IStatisticalUnit
        {
            var unitType = after.GetType();
            var props = unitType.GetProperties();
            var daa = await _userService.GetDataAccessAttributes(
                userId,
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(unitType));
            return (from prop in props
                    let valueBefore = unitType.GetProperty(prop.Name).GetValue(before, null)?.ToString() ?? ""
                    let valueAfter = unitType.GetProperty(prop.Name).GetValue(after, null)?.ToString() ?? ""
                    where prop.Name != nameof(IStatisticalUnit.RegId)
                          && daa.Contains(DataAccessAttributesHelper.GetName(unitType, prop.Name))
                          && valueAfter != valueBefore
                    select new ChangedField {Name = prop.Name, Before = valueBefore, After = valueAfter})
                .ToList();
        }

        private async Task<IStatisticalUnit> GetStatisticalUnitByIdAndType(int id, StatUnitTypes type, bool showDeleted)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return await GetUnitById<StatisticalUnit>(id, showDeleted, query => query
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress)
                    );
                case StatUnitTypes.LegalUnit:
                    return await GetUnitById<LegalUnit>(id, showDeleted, query => query
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress)
                        .Include(v => v.LocalUnits)
                    );
                case StatUnitTypes.EnterpriseUnit:
                    return await GetUnitById<EnterpriseUnit>(id, showDeleted, query => query
                        .Include(x => x.LocalUnits)
                        .Include(x => x.LegalUnits)
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress));
                case StatUnitTypes.EnterpriseGroup:
                    return await GetUnitById<EnterpriseGroup>(id, showDeleted, query => query
                        .Include(x => x.LegalUnits)
                        .Include(x => x.EnterpriseUnits)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        private static IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
        {
            var unitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type);
            return (IStatisticalUnit) Activator.CreateInstance(unitType);
        }

        private IQueryable<T> GetUnitsList<T>(bool showDeleted) where T : class, IStatisticalUnit
        {
            var query = _dbContext.Set<T>().Where(unit => unit.ParrentId == null);
            if (!showDeleted)
            {
                query = query.Where(v => !v.IsDeleted);
            }
            return query;
        }

        private async Task<T> GetUnitById<T>(int id, bool showDeleted, Func<IQueryable<T>, IQueryable<T>> work = null)
            where T : class, IStatisticalUnit
        {
            var query = GetUnitsList<T>(showDeleted);
            if (work != null)
            {
                query = work(query);
            }
            return await query.SingleAsync(v => v.RegId == id);
        }
    }
}
