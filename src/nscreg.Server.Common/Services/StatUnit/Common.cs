using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Utilities;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Общий сервис стат. единиц
    /// </summary>
    internal class Common
    {
        private readonly NSCRegDbContext _dbContext;

        public Common(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public static readonly Expression<Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>>> UnitMapping =
            u => Tuple.Create(
                new CodeLookupVm {Id = u.RegId, Code = u.StatId, Name = u.Name},
                u.GetType());

        private static readonly Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>> UnitMappingFunc =
            UnitMapping.Compile();

        /// <summary>
        /// Метод получения стат. единиц по Id и типу
        /// </summary>
        /// <param name="id">Id стат. еденицы</param>
        /// <param name="type">Тип</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<IStatisticalUnit> GetStatisticalUnitByIdAndType(
            int id,
            StatUnitTypes type,
            bool showDeleted)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return await GetUnitById<StatisticalUnit>(
                        id,
                        showDeleted,
                        query => query
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.ActualAddress)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.PersonsUnits)
                            .ThenInclude(v => v.Person));
                case StatUnitTypes.LegalUnit:
                    return await GetUnitById<LegalUnit>(
                        id,
                        showDeleted,
                        query => query
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.ActualAddress)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.LocalUnits)
                            .Include(v => v.PersonsUnits)
                            .ThenInclude(v => v.Person));
                case StatUnitTypes.EnterpriseUnit:
                    return await GetUnitById<EnterpriseUnit>(
                        id,
                        showDeleted,
                        query => query
                            .Include(x => x.LegalUnits)
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.ActualAddress)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.PersonsUnits)
                            .ThenInclude(v => v.Person));
                case StatUnitTypes.EnterpriseGroup:
                    return await GetUnitById<EnterpriseGroup>(
                        id,
                        showDeleted,
                        query => query
                            .Include(x => x.EnterpriseUnits)
                            .Include(v => v.Address)
                            .ThenInclude(v => v.Region)
                            .Include(v => v.ActualAddress)
                            .ThenInclude(v => v.Region));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        /// <summary>
        /// Метод получения спика стат. единиц
        /// </summary>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public IQueryable<T> GetUnitsList<T>(bool showDeleted) where T : class, IStatisticalUnit
        {
            var query = _dbContext.Set<T>().Where(unit => unit.ParentId == null);
            if (!showDeleted) query = query.Where(v => !v.IsDeleted);
            return query;
        }

        /// <summary>
        /// Метод получения стат. единиц по Id
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        public async Task<T> GetUnitById<T>(
            int id,
            bool showDeleted,
            Func<IQueryable<T>, IQueryable<T>> work = null)
            where T : class, IStatisticalUnit
        {
            var query = GetUnitsList<T>(showDeleted);
            if (work != null)
            {
                query = work(query);
            }
            var unitById = await query.SingleAsync(v => v.RegId == id);
            return unitById;
        }

        /// <summary>
        /// Метод отслеживания связанных историй стат. единицы
        /// </summary>
        /// <param name="unit">Стат. еденица</param>
        /// <param name="hUnit">История стат. еденицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="changeReason">Причина изменения</param>
        /// <param name="comment">Комментарий</param>
        /// <param name="changeDateTime">Дата изменения</param>
        /// <param name="unitsHistoryHolder">Хранитель истории стат. еденицы</param>
        public void TrackRelatedUnitsHistory<TUnit>(
            TUnit unit,
            TUnit hUnit,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            UnitsHistoryHolder unitsHistoryHolder) 
            where TUnit : class, IStatisticalUnit, new()
        {
            var historyParentId = _dbContext.Set<TUnit>().FirstOrDefault(x => x.ParentId == unit.RegId && x.EndPeriod == changeDateTime).RegId;
            switch (unit.GetType().Name)
            {
                case nameof(LocalUnit):
                {
                    var localUnit = unit as LocalUnit;

                    if (localUnit?.LegalUnitId != unitsHistoryHolder.HistoryUnits.legalUnitId)
                        TrackUnithistoryFor<LegalUnit>(localUnit?.LegalUnitId, userId, changeReason, comment, changeDateTime);

                    break;
                }

                case nameof(LegalUnit):
                {
                    var legalUnit = unit as LegalUnit;

                    TrackHistoryForListOfUnitsFor<LocalUnit>(
                    () => legalUnit?.LocalUnits.Where(x => x.ParentId == null).Select(x => x.RegId).ToList(),
                    () => unitsHistoryHolder.HistoryUnits.localUnitsIds,
                    userId,
                    changeReason,
                    comment,
                    changeDateTime, work:
                    (historyUnit) =>
                    {
                        var localUnit = historyUnit as LocalUnit;
                        if (localUnit == null) return;
                        if (unitsHistoryHolder.HistoryUnits.localUnitsIds.Count == 0)
                        {
                            localUnit.LegalUnit = null;
                            localUnit.LegalUnitId = null;
                            return;
                        }

                        if (unitsHistoryHolder.HistoryUnits.localUnitsIds.Contains(localUnit.RegId))
                            localUnit.LegalUnitId = historyParentId;
                    });

                    if (legalUnit?.EnterpriseUnitRegId != unitsHistoryHolder.HistoryUnits.enterpriseUnitId)
                        TrackUnithistoryFor<EnterpriseUnit>(legalUnit?.EnterpriseUnitRegId, userId, changeReason, comment, changeDateTime);

                    break;
                }

                case nameof(EnterpriseUnit):
                {
                    var enterpriseUnit = unit as EnterpriseUnit;

                    TrackHistoryForListOfUnitsFor<LegalUnit>(
                        () => enterpriseUnit?.LegalUnits.Where(x => x.ParentId == null).Select(x => x.RegId).ToList(),
                        () => unitsHistoryHolder.HistoryUnits.legalUnitsIds,
                        userId,
                        changeReason,
                        comment,
                        changeDateTime, work:
                        (historyUnit) =>
                        {
                            var legalUnit = historyUnit as LegalUnit;
                            if (legalUnit == null) return;
                            if (unitsHistoryHolder.HistoryUnits.legalUnitsIds.Count == 0)
                            {
                                legalUnit.EnterpriseUnit = null;
                                legalUnit.EnterpriseUnitRegId = null;
                                return;
                            }

                            if (unitsHistoryHolder.HistoryUnits.legalUnitsIds.Contains(legalUnit.RegId))
                                legalUnit.EnterpriseUnitRegId = historyParentId;

                        });

                    if (enterpriseUnit?.EntGroupId != unitsHistoryHolder.HistoryUnits.enterpriseGroupId)
                        TrackUnithistoryFor<EnterpriseGroup>(enterpriseUnit?.EntGroupId, userId, changeReason, comment, changeDateTime);

                    break;
                }

                case nameof(EnterpriseGroup):
                {
                    var enterpriseGroup = unit as EnterpriseGroup;

                    TrackHistoryForListOfUnitsFor<EnterpriseUnit>(
                        () => enterpriseGroup?.EnterpriseUnits.Where(x => x.ParentId == null).Select(x => x.RegId).ToList(),
                        () => unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds,
                        userId,
                        changeReason,
                        comment,
                        changeDateTime, work:
                        (historyUnit) =>
                        {
                            var enterpriseUnit = historyUnit as EnterpriseUnit;
                            if (enterpriseUnit == null) return;
                            if (unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds.Count == 0)
                            {
                                enterpriseUnit.EnterpriseGroup = null;
                                enterpriseUnit.EntGroupId = null;
                                return;
                            }

                            if (unitsHistoryHolder.HistoryUnits.enterpriseUnitsIds.Contains(enterpriseUnit.RegId))
                                enterpriseUnit.EntGroupId = historyParentId;
                        });
                    break;
                }

                default:
                    throw new NotImplementedException();
            }
        }

        /// <summary>
        /// Метод отслеживания истории списка для стат. единицы
        /// </summary>
        /// <param name="unitIdsSelector"></param>
        /// <param name="hUnitIdsSelector"></param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="changeReason">Причина изменения</param>
        /// <param name="comment">Комментарий</param>
        /// <param name="changeDateTime">Дата изменения</param>
        /// <param name="work">В работе</param>
        private void TrackHistoryForListOfUnitsFor<TUnit>(
            Func<List<int>> unitIdsSelector,
            Func<List<int>> hUnitIdsSelector,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            Action<IStatisticalUnit> work = null)
            where TUnit : class, IStatisticalUnit, new()
        {
            var unitIds = unitIdsSelector();
            var hUnitIds = hUnitIdsSelector();

            if (unitIds.SequenceEqual(hUnitIds)) return;

            foreach (var changeTrackingUnitId in unitIds.Union(hUnitIds).Except(unitIds.Intersect(hUnitIds)))
                TrackUnithistoryFor<TUnit>(changeTrackingUnitId, userId, changeReason, comment, changeDateTime, work);
        }

        /// <summary>
        /// Метод отслеживания истории  стат. единицы
        /// </summary>
        /// <param name="unitId">Id стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="changeReason">Причина изменения</param>
        /// <param name="comment">Комментарий</param>
        /// <param name="changeDateTime">Дата изменения</param>
        /// <param name="work">В работе</param>
        public void TrackUnithistoryFor<TUnit>(
            int? unitId,
            string userId,
            ChangeReasons changeReason,
            string comment,
            DateTime changeDateTime,
            Action<IStatisticalUnit> work = null)
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = _dbContext.Set<TUnit>().SingleOrDefault(x => x.RegId == unitId);
            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);

            work?.Invoke(hUnit);

            hUnit.UserId = userId;
            hUnit.ChangeReason = changeReason;
            hUnit.EditComment = comment;

            _dbContext.Set<TUnit>().Add((TUnit)TrackHistory(unit, hUnit, changeDateTime));
        }

        /// <summary>
        /// Метод отслеживания истории
        /// </summary>
        /// <param name="unit">Стат. единица</param>
        /// <param name="hUnit">История стат. единицы</param>
        /// <param name="changeDateTime">Дата изменения</param>
        /// <returns></returns>
        public static IStatisticalUnit TrackHistory(
            IStatisticalUnit unit,
            IStatisticalUnit hUnit,
            DateTime? changeDateTime = null)
        {
            var timeStamp = changeDateTime ?? DateTime.Now;
            unit.StartPeriod = timeStamp;
            hUnit.RegId = 0;
            hUnit.EndPeriod = timeStamp;
            hUnit.ParentId = unit.RegId;
            return hUnit;
        }

        /// <summary>
        /// Метод инициализации атрибутов доступа к данным
        /// </summary>
        /// <param name="userService">Сервис пользователя</param>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="type">Тип</param>
        /// <returns></returns>
        public async Task<ISet<string>> InitializeDataAccessAttributes<TModel>(
            UserService userService,
            TModel data,
            string userId,
            StatUnitTypes type)
            where TModel : IStatUnitM
        {
            var dataAccess = (data.DataAccess ?? Enumerable.Empty<string>()).ToImmutableHashSet();
            var userDataAccess = await userService.GetDataAccessAttributes(userId, type);
            var dataAccessChanges = dataAccess.Except(userDataAccess);
            if (dataAccessChanges.Count != 0)
            {
                //TODO: Optimize throw only if this field changed
                throw new BadRequestException(nameof(Resource.DataAccessConflict));
            }
            data.DataAccess = dataAccess;
            return dataAccess;
        }

        /// <summary>
        /// Метод определения доступа
        /// </summary>
        /// <param name="dataAccess">Доступ к данным</param>
        /// <param name="property">Свойство</param>
        /// <returns></returns>
        public static bool HasAccess<T>(ICollection<string> dataAccess, Expression<Func<T, object>> property)
        {
            var name = ExpressionUtils.GetExpressionText(property);
            return dataAccess.Contains(DataAccessAttributesHelper.GetName<T>(name));
        }

        /// <summary>
        /// Метод добавления адресов
        /// </summary>
        /// <param name="unit">Стат. единица</param>
        /// <param name="data">Данные</param>
        public void AddAddresses<TUnit>(IStatisticalUnit unit, IStatUnitM data) where TUnit: IStatisticalUnit
        {
            if (data.Address != null && !data.Address.IsEmpty() && HasAccess<TUnit>(data.DataAccess, v => v.Address))
                unit.Address = GetAddress(data.Address);
            else unit.Address = null;
            if (data.ActualAddress != null && !data.ActualAddress.IsEmpty() && HasAccess<TUnit>(data.DataAccess, v => v.ActualAddress))
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            else unit.ActualAddress = null;
        }

        /// <summary>
        /// Метод проверки уникальности имени адреса
        /// </summary>
        /// <param name="name">Имя</param>
        /// <param name="address">адрес</param>
        /// <param name="actualAddress">Актуальный адрес</param>
        /// <returns></returns>
        public bool NameAddressIsUnique<T>(
            string name,
            AddressM address,
            AddressM actualAddress)
            where T : class, IStatisticalUnit
        {
            if (address == null) address = new AddressM();
            if (actualAddress == null) actualAddress = new AddressM();
            return _dbContext.Set<T>()
                .Include(a => a.Address)
                .Include(aa => aa.ActualAddress)
                .Where(u => u.Name == name)
                .All(unit =>
                    !address.Equals(unit.Address)
                    && !actualAddress.Equals(unit.ActualAddress));
        }

        public static T ToUnitLookupVm<T>(IStatisticalUnit unit) where T : UnitLookupVm, new()
            => ToUnitLookupVm<T>(UnitMappingFunc(unit));

        public static IEnumerable<UnitLookupVm> ToUnitLookupVm(IEnumerable<Tuple<CodeLookupVm, Type>> source)
            => source.Select(ToUnitLookupVm<UnitLookupVm>);

        /// <summary>
        /// Метод преобразования стат. единицы в справочник вью модели
        /// </summary>
        /// <param name="unit">Стат единица</param>
        /// <returns></returns>
        private static T ToUnitLookupVm<T>(Tuple<CodeLookupVm, Type> unit) where T : UnitLookupVm, new()
        {
            var vm = new T
            {
                Type = StatisticalUnitsTypeHelper.GetStatUnitMappingType(unit.Item2)
            };
            Mapper.Map<CodeLookupVm, UnitLookupVm>(unit.Item1, vm);
            return vm;
        }

        /// <summary>
        /// Метод получения адреса
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        private Address GetAddress(AddressM data)
            => _dbContext.Address.SingleOrDefault(a =>
                   a.Id == data.Id &&
                   a.AddressPart1 == data.AddressPart1 &&
                   a.AddressPart2 == data.AddressPart2 &&
                   a.AddressPart3 == data.AddressPart3 &&
                   a.Region.Code == data.Region.Code &&
                   a.GpsCoordinates == data.GpsCoordinates)
               ?? new Address
               {
                   AddressPart1 = data.AddressPart1,
                   AddressPart2 = data.AddressPart2,
                   AddressPart3 = data.AddressPart3,
                   Region = _dbContext.Regions.SingleOrDefault(r => r.Code == data.Region.Code),
                   GpsCoordinates = data.GpsCoordinates
               };
    }
}
