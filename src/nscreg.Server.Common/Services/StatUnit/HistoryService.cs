using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.History;
using nscreg.Utilities;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис истории
    /// </summary>
    public class HistoryService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;
        private readonly ForeingKeysResolver _foreignKeysResolver;

        public HistoryService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
            _foreignKeysResolver = new ForeingKeysResolver(dbContext);
        }

        /// <summary>
        ///  Метод получения истории стат. единицы
        /// </summary>
        /// <param name="type">Тип стат. единцы</param>
        /// <param name="id">Id стат. единцы</param>
        /// <returns></returns>
        public async Task<object> ShowHistoryAsync(StatUnitTypes type, int id)
        {
            var history = type == StatUnitTypes.EnterpriseGroup
                ? await FetchUnitHistoryAsync<EnterpriseGroup>(id)
                : await FetchUnitHistoryAsync<StatisticalUnit>(id);
            var result = history.ToArray();
            return SearchVm.Create(result, result.Length);
        }

        /// <summary>
        /// Метод получения подробной истории стат. единицы
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<object> ShowHistoryDetailsAsync(StatUnitTypes type, int id, string userId)
        {
            var history = type == StatUnitTypes.EnterpriseGroup
                ? await FetchDetailedUnitHistoryAsync<EnterpriseGroup>(id, userId)
                : await FetchDetailedUnitHistoryAsync<StatisticalUnit>(id, userId);
            var result = history.ToArray();
            return SearchVm.Create(result, result.Length);
        }

        /// <summary>
        ///
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        private async Task<IEnumerable<ChangedField>> FetchDetailedUnitHistoryAsync<T>(int id, string userId)
            where T : class, IStatisticalUnit
        {
            var result = await _dbContext.Set<T>()
                .Join(_dbContext.Set<T>(),
                    unitAfter => unitAfter.ParentId ?? unitAfter.RegId,
                    unitBefore => unitBefore.ParentId,
                    (unitAfter, unitBefore) => new {UnitAfter = unitAfter, UnitBefore = unitBefore})
                .Where(x => x.UnitAfter.RegId == id && x.UnitAfter.StartPeriod == x.UnitBefore.EndPeriod)
                .FirstOrDefaultAsync();
            return result == null
                ? new List<ChangedField>()
                : await CutUnchangedFields(result.UnitAfter, result.UnitBefore, userId);
        }

        /// <summary>
        /// Метод возвращающий неизменённые обрезанные поля
        /// </summary>
        /// <param name="after">До</param>
        /// <param name="before">После</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        private async Task<IEnumerable<ChangedField>> CutUnchangedFields<T>(T after, T before, string userId)
            where T : class, IStatisticalUnit
        {
            var unitType = after.GetType();
            var daa = await _userService.GetDataAccessAttributes(
                userId,
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(unitType));
            var cahangedFields =
                from prop in unitType.GetProperties()
                let valueBefore = unitType.GetProperty(prop.Name).GetValue(before, null)?.ToString() ?? ""
                let valueAfter = unitType.GetProperty(prop.Name).GetValue(after, null)?.ToString() ?? ""
                where prop.Name != nameof(IStatisticalUnit.RegId)
                      && daa.HasWritePermission(DataAccessAttributesHelper.GetName(unitType, prop.Name))
                      && valueAfter != valueBefore
                select new ChangedField {Name = prop.Name, Before = valueBefore, After = valueAfter};

            var result = cahangedFields.ToArray();

            foreach(var historyChangedField in result.Where(x => _foreignKeysResolver.Keys.Contains(x.Name)).Select(x=> x).ToArray())
            {
                if (historyChangedField != null)
                    _foreignKeysResolver[historyChangedField.Name](historyChangedField);
            }



            return result.ToArray();
        }

        /// <summary>
        /// Метод получения истории стат. единицы
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        private async Task<IEnumerable<object>> FetchUnitHistoryAsync<T>(int id)
            where T : class, IStatisticalUnit
            => await _dbContext.Set<T>()
                .Join(_dbContext.Users,
                    unit => unit.UserId,
                    user => user.Id,
                    (unit, user) => new {Unit = unit, User = user})
                .Where(x => x.Unit.ParentId == id || x.Unit.RegId == id)
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
