using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Data.Entities.History;
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
        private readonly Common _commonSvc;

        public HistoryService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
            _foreignKeysResolver = new ForeingKeysResolver(dbContext);
            _commonSvc = new Common(dbContext);
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
                ? await FetchUnitHistoryAsync<EnterpriseGroup, EnterpriseGroupHistory>(id)
                : await FetchUnitHistoryAsync<StatisticalUnit, StatisticalUnitHistory>(id);
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
                ? await FetchDetailedUnitHistoryAsync<EnterpriseGroup, EnterpriseGroupHistory>(id, userId)
                : await FetchDetailedUnitHistoryAsync<StatisticalUnit, StatisticalUnitHistory>(id, userId);
            var result = history.ToArray();
            return SearchVm.Create(result, result.Length);
        }

        /// <summary>
        ///
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        private async Task<IEnumerable<ChangedField>> FetchDetailedUnitHistoryAsync<TUnit, THistory>(int id, string userId)
            where TUnit : class, IStatisticalUnit
            where THistory : class, IStatisticalUnitHistory
        {
            var actualToHistoryComparingResult = await _dbContext.Set<TUnit>()
                .Join(_dbContext.Set<THistory>(),
                    unitAfter => unitAfter.RegId,
                    unitBefore => unitBefore.ParentId,
                    (unitAfter, unitBefore) => new {UnitAfter = unitAfter, UnitBefore = unitBefore})
                .Where(x => x.UnitAfter.RegId == id && x.UnitAfter.StartPeriod == x.UnitBefore.EndPeriod)
                .FirstOrDefaultAsync();

           
            var historyToHistoryComparingResult = await _dbContext.Set<THistory>()
                    .Join(_dbContext.Set<THistory>(),
                        unitAfter => unitAfter.ParentId,
                        unitBefore => unitBefore.ParentId,
                        (unitAfter, unitBefore) => new { UnitAfter = unitAfter, UnitBefore = unitBefore })
                    .Where(x => x.UnitAfter.RegId == id && x.UnitAfter.StartPeriod == x.UnitBefore.EndPeriod)
                    .FirstOrDefaultAsync();


            return actualToHistoryComparingResult == null && historyToHistoryComparingResult == null
                ? new List<ChangedField>()
                : actualToHistoryComparingResult == null ? await CutUnchangedFields(_commonSvc.MapHistoryUnitToUnit(historyToHistoryComparingResult.UnitAfter), _commonSvc.MapHistoryUnitToUnit(historyToHistoryComparingResult.UnitBefore), userId)
                    : await CutUnchangedFields(actualToHistoryComparingResult.UnitAfter, _commonSvc.MapHistoryUnitToUnit(actualToHistoryComparingResult.UnitBefore), userId);
        }

        /// <summary>
        /// Метод возвращающий неизменённые обрезанные поля
        /// </summary>
        /// <param name="after">После</param>
        /// <param name="before">До</param>
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
                      && daa.HasWriteOrReadPermission(DataAccessAttributesHelper.GetName(unitType, prop.Name))
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
        private async Task<IEnumerable<object>> FetchUnitHistoryAsync<TUnit, THistory>(int id)
            where TUnit : class, IStatisticalUnit
            where THistory : class, IStatisticalUnitHistory
        {
            var actualUnit = await _dbContext.Set<TUnit>()
                .Join(_dbContext.Users,
                    unit => unit.UserId,
                    user => user.Id,
                    (unit, user) => new { Unit = unit, User = user })
                .Where(x => x.Unit.RegId == id)
                .Select(x => new
                {
                    x.Unit.RegId,
                    x.User.Name,
                    x.Unit.ChangeReason,
                    x.Unit.EditComment,
                    x.Unit.StartPeriod,
                    x.Unit.EndPeriod
                }).ToListAsync();

            var historyUnits = await _dbContext.Set<THistory>()
                .Join(_dbContext.Users,
                    unit => unit.UserId,
                    user => user.Id,
                    (unit, user) => new { Unit = unit, User = user })
                .Where(x => x.Unit.ParentId == id)
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

            actualUnit.AddRange(historyUnits);
            return actualUnit;
        }
             
    }
}
