using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.History;
using nscreg.Utilities;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class HistoryService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;

        public HistoryService(NSCRegDbContext dbContext)
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

        private async Task<IEnumerable<ChangedField>> FetchDetailedUnitHistoryAsync<T>(int id, string userId)
            where T : class, IStatisticalUnit
        {
            var result = await _dbContext.Set<T>()
                .Join(_dbContext.Set<T>(),
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
            var daa = await _userService.GetDataAccessAttributes(
                userId,
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(unitType));
            var result =
                from prop in unitType.GetProperties()
                let valueBefore = unitType.GetProperty(prop.Name).GetValue(before, null)?.ToString() ?? ""
                let valueAfter = unitType.GetProperty(prop.Name).GetValue(after, null)?.ToString() ?? ""
                where prop.Name != nameof(IStatisticalUnit.RegId)
                      && daa.Contains(DataAccessAttributesHelper.GetName(unitType, prop.Name))
                      && valueAfter != valueBefore
                select new ChangedField {Name = prop.Name, Before = valueBefore, After = valueAfter};

            return result.ToArray();
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
    }
}
