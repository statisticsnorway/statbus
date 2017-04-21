using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Core;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.ViewFeatures.Internal;
using nscreg.Data.Helpers;
using nscreg.Resources.Languages;
using nscreg.Server.Classes;
using nscreg.Server.Models.Links;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.StatUnits.History;
using nscreg.Utilities;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Services
{
    public class StatUnitService
    {
        private readonly Dictionary<StatUnitTypes, Action<int, bool, string>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _dbContext;
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;

        private static readonly Expression<Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>>> UnitMapping = u =>
            new Tuple<CodeLookupVm, Type>(
                new CodeLookupVm()
                {
                    Id = u.RegId,
                    Code = u.StatId,
                    Name = u.Name,
                }, u.GetType());

        private static readonly Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>> UnitMappingFunc = UnitMapping.Compile();

        public StatUnitService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _readCtx = new ReadContext(dbContext);
            _userService = new UserService(dbContext);

            _deleteUndeleteActions = new Dictionary<StatUnitTypes, Action<int, bool, string>>
            {
                [StatUnitTypes.EnterpriseGroup] = DeleteUndeleteEnterpriseGroupUnit,
                [StatUnitTypes.EnterpriseUnit] = DeleteUndeleteEnterpriseUnit,
                [StatUnitTypes.LocalUnit] = DeleteUndeleteLocalUnit,
                [StatUnitTypes.LegalUnit] = DeleteUndeleteLegalUnit
            };
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
                .Join(_dbContext.Set<T>(),
                    unitAfter => unitAfter.ParrentId ?? unitAfter.RegId,
                    unitBefore => unitBefore.ParrentId,
                    (unitAfter, unitBefore) => new {UnitAfter = unitAfter, UnitBefore = unitBefore})
                .Where(x => x.UnitAfter.RegId == id
                            && x.UnitAfter.StartPeriod == x.UnitBefore.EndPeriod)
                .FirstOrDefaultAsync();
            return result == null ? new List<ChangedField>() : await CutUnchangedFields(result.UnitAfter, result.UnitBefore, userId);
        }

        private async  Task<IEnumerable<ChangedField>> CutUnchangedFields<T>(T after, T before, string userId)
            where T : class, IStatisticalUnit
        {
            var unitType = after.GetType();
            var props = unitType.GetProperties();
            var daa = await _userService.GetDataAccessAttributes(userId, StatisticalUnitsTypeHelper.GetStatUnitMappingType(unitType));
            return (from prop in props
                    let valueBefore = unitType.GetProperty(prop.Name).GetValue(before, null)?.ToString() ?? ""
                    let valueAfter = unitType.GetProperty(prop.Name).GetValue(after, null)?.ToString() ?? ""
                    where daa.Contains($"{unitType.Name}.{prop.Name}") && valueAfter != valueBefore
                    select new ChangedField {Name = prop.Name, Before = valueBefore, After = valueAfter})
                .ToList();
        }

        #region SEARCH

        public async Task<SearchVm> Search(SearchQueryM query, string userId, bool deletedOnly = false)
        {
            var propNames = await _userService.GetDataAccessAttributes(userId, null);
            var unit =
                _readCtx.StatUnits
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType =
                                x is LocalUnit
                                    ? StatUnitTypes.LocalUnit
                                    : x is LegalUnit
                                        ? StatUnitTypes.LegalUnit
                                        : StatUnitTypes.EnterpriseUnit
                            });
            var group =
                _readCtx.EnterpriseGroups
                    .Where(x => x.ParrentId == null && x.IsDeleted == deletedOnly)
                    .Include(x => x.Address)
                    .Where(x => query.IncludeLiquidated || string.IsNullOrEmpty(x.LiqReason))
                    .Select(
                        x =>
                            new
                            {
                                x.RegId,
                                x.Name,
                                x.Address,
                                x.Turnover,
                                x.Employees,
                                UnitType = StatUnitTypes.EnterpriseGroup
                            });
            var filtered = unit.Concat(group);

            if (!string.IsNullOrEmpty(query.Wildcard))
            {
                Predicate<string> checkWildcard =
                    superStr => !string.IsNullOrEmpty(superStr) && superStr.Contains(query.Wildcard);
                filtered = filtered.Where(x =>
                    x.Name.Contains(query.Wildcard)
                    || x.Address != null
                    && (checkWildcard(x.Address.AddressPart1)
                        || checkWildcard(x.Address.AddressPart2)
                        || checkWildcard(x.Address.AddressPart3)
                        || checkWildcard(x.Address.AddressPart4)
                        || checkWildcard(x.Address.AddressPart5)
                        || checkWildcard(x.Address.GeographicalCodes)));
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

            var total = filtered.Count();
            var totalPages = (int) Math.Ceiling((double) total / query.PageSize);
            var skip = query.PageSize * (Math.Min(totalPages, query.Page) - 1);

            var result = filtered
                .Skip(skip)
                .Take(query.PageSize)
                .Select(x => SearchItemVm.Create(x, x.UnitType, propNames))
                .ToList();

            return SearchVm.Create(result, total);
        }

        public async Task<List<UnitLookupVm>> Search(string code, int limit = 5)
        {
            Expression<Func<IStatisticalUnit, bool>> filter = unit =>
                unit.StatId != null && unit.StatId.StartsWith(code) && unit.ParrentId == null && !unit.IsDeleted;
            var units = _readCtx.StatUnits.Where(filter).Select(UnitMapping);
            var eg = _readCtx.EnterpriseGroups.Where(filter).Select(UnitMapping);
            var list = await units.Concat(eg).Take(limit).ToListAsync();
            return ToUnitLookupVm(list).ToList();
        }

        #endregion

        #region VIEW

        internal async Task<object> GetUnitByIdAndType(int id, StatUnitTypes type, string userId, bool showDeleted)
        {
            var item = await GetStatisticalUnitByIdAndType(id, type, showDeleted);
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return SearchItemVm.Create(item, item.UnitType, dataAttributes);
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
                        .Include(x => x.EnterpriseUnits)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        #endregion

        #region DELETE

        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete, string userId)
        {
            _deleteUndeleteActions[unitType](id, toDelete, userId);
        }

        private void DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseGroup();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseGroups.Add((EnterpriseGroup) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLegalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LegalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LegalUnits.Add((LegalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteLocalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LocalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LocalUnits.Add((LocalUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        private void DeleteUndeleteEnterpriseUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseUnits.Add((EnterpriseUnit) TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        #endregion

        #region CREATE

        public async Task CreateLegalUnit(LegalUnitCreateM data, string userId)
        {
            await CreateUnitContext<LegalUnit, LegalUnitCreateM>(data, userId, unit =>
            {
                if (HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                    unit.LocalUnits.Clear();
                    foreach (var localUnit in localUnits)
                    {
                        unit.LocalUnits.Add(localUnit);
                    }
                }
                return Task.CompletedTask;
            });
        }

        public async Task CreateLocalUnit(LocalUnitCreateM data, string userId)
        {
            await CreateUnitContext<LocalUnit, LocalUnitCreateM>(data, userId, null);
        }

        public async Task CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
        {
            await CreateUnitContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId)).ToList();
                foreach (var localUnit in localUnits)
                {
                    unit.LocalUnits.Add(localUnit);
                }
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }
                return Task.CompletedTask;
            });
        }

        public async Task CreateEnterpriseGroupUnit(EnterpriseGroupCreateM data, string userId)
        {
            await CreateContext<EnterpriseGroup, EnterpriseGroupCreateM>(data, userId, unit =>
            {
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId))
                        .ToList();
                    foreach (var enterprise in enterprises)
                    {
                        unit.EnterpriseUnits.Add(enterprise);
                    }
                }
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.LegalUnits))
                {
                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                    foreach (var legalUnit in legalUnits)
                    {
                        unit.LegalUnits.Add(legalUnit);
                    }
                }
                return Task.CompletedTask;
            });
        }

        private async Task CreateContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work
        ) where TModel : IStatUnitM where TUnit : class, IStatisticalUnit, new()
        {
            var unit = new TUnit();
            await InitializeDataAccessAttributes(data, userId, unit.UnitType);
            Mapper.Map(data, unit);
            AddAddresses(unit, data);

            if (!NameAddressIsUnique<TUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            if (work != null)
            {
                await work(unit);
            }

            unit.UserId = userId;

            _dbContext.Set<TUnit>().Add(unit);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private async Task CreateUnitContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work
        ) where TModel : StatUnitModelBase where TUnit : StatisticalUnit, new()
        {
            await CreateContext<TUnit, TModel>(data, userId, async unit =>
            {
                if (HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                {
                    var activitiesList = data.Activities ?? new List<ActivityM>();

                    //Get Ids for codes
                    var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
                    var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

                    var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                        nameof(Resource.ActivityCategoryLookup),
                        await activityService.List(false, v => codesList.Contains(v.Code))
                    );

                    unit.ActivitiesUnits.AddRange(activitiesList.Select(v =>
                        {
                            var activity = Mapper.Map<ActivityM, Activity>(v);
                            activity.Id = 0;
                            activity.ActivityRevx = codesLookup.Get(v.ActivityRevxCategory.Code).Id;
                            activity.UpdatedBy = userId;
                            return new ActivityStatisticalUnit {Activity = activity};
                        }
                    ));
                }

                if (work != null)
                {
                    await work(unit);
                }
            });
        }

        #endregion

        #region EDIT

        public async Task EditLegalUnit(LegalUnitEditM data, string userId)
        {
            await EditUnitContext<LegalUnit, LegalUnitEditM>(data, m => m.RegId.Value, userId, unit =>
            {
                if (HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                    unit.LocalUnits.Clear();
                    foreach (var localUnit in localUnits)
                    {
                        unit.LocalUnits.Add(localUnit);
                    }
                }
                return Task.CompletedTask;
            });
        }

        public async Task EditLocalUnit(LocalUnitEditM data, string userId)
        {
            await EditUnitContext<LocalUnit, LocalUnitEditM>(data, v => v.RegId.Value, userId, null);
        }

        public async Task EditEnterpiseUnit(EnterpriseUnitEditM data, string userId)
        {
            await EditUnitContext<EnterpriseUnit, EnterpriseUnitEditM>(data, m => m.RegId.Value, userId, unit =>
            {
                if (HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                    unit.LocalUnits.Clear();
                    foreach (var localUnit in localUnits)
                    {
                        unit.LocalUnits.Add(localUnit);
                    }
                }
                if (HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LegalUnits))
                {
                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
                    unit.LegalUnits.Clear();
                    foreach (var legalUnit in legalUnits)
                    {
                        unit.LegalUnits.Add(legalUnit);
                    }
                }
                return Task.CompletedTask;
            });
        }

        public async Task EditEnterpiseGroup(EnterpriseGroupEditM data, string userId)
        {
            await EditContext<EnterpriseGroup, EnterpriseGroupEditM>(data, m => m.RegId.Value, userId, unit =>
            {
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
                    unit.EnterpriseUnits.Clear();
                    foreach (var enterprise in enterprises)
                    {
                        unit.EnterpriseUnits.Add(enterprise);
                    }
                }
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.LegalUnits))
                {
                    unit.LegalUnits.Clear();
                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                    foreach (var legalUnit in legalUnits)
                    {
                        unit.LegalUnits.Add(legalUnit);
                    }
                }
                return Task.CompletedTask;
            });
        }

        private async Task EditContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work
        ) where TModel : IStatUnitM where TUnit : class, IStatisticalUnit, new()
        {
            var unit = (TUnit) await ValidateChanges<TUnit>(data, idSelector(data));
            await InitializeDataAccessAttributes(data, userId, unit.UnitType);

            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            Mapper.Map(data, unit);

            //External Mappings
            if (work != null)
            {
                await work(unit);
            }

            if (IsNoChanges(unit, hUnit)) return;
            AddAddresses(unit, data); //TODO: AFTER NO CHANGES? BUG?
            unit.UserId = userId;
            unit.ChangeReason = data.ChangeReason;
            unit.EditComment = data.EditComment;

            _dbContext.Set<TUnit>().Add((TUnit) TrackHistory(unit, hUnit));

            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                //TODO: Processing Validation Errors
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private async Task EditUnitContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work
        ) where TModel : StatUnitModelBase where TUnit : StatisticalUnit, new()
        {
            await EditContext<TUnit, TModel>(data, idSelector, userId, async unit =>
            {
                //Merge activities
                if (HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                {
                    var activities = new List<ActivityStatisticalUnit>();
                    var srcActivities = unit.ActivitiesUnits.ToDictionary(v => v.ActivityId);
                    var activitiesList = data.Activities ?? new List<ActivityM>();

                    //Get Ids for codes
                    var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
                    var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

                    var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                        nameof(Resource.ActivityCategoryLookup),
                        await activityService.List(false, v => codesList.Contains(v.Code))
                    );

                    foreach (var model in activitiesList)
                    {
                        ActivityStatisticalUnit activityAndUnit;

                        if (model.Id.HasValue && srcActivities.TryGetValue(model.Id.Value, out activityAndUnit))
                        {
                            var currentActivity = activityAndUnit.Activity;
                            if (model.ActivityRevxCategory.Id == currentActivity.ActivityRevx &&
                                ObjectComparer.SequentialEquals(model, currentActivity))
                            {
                                activities.Add(activityAndUnit);
                                continue;
                            }
                        }
                        var newActivity = new Activity();
                        Mapper.Map(model, newActivity);
                        newActivity.UpdatedBy = userId;
                        newActivity.ActivityRevx = codesLookup.Get(model.ActivityRevxCategory.Code).Id;
                        activities.Add(new ActivityStatisticalUnit() {Activity = newActivity});
                    }
                    var activitiesUnits = unit.ActivitiesUnits;
                    activitiesUnits.Clear();
                    unit.ActivitiesUnits.AddRange(activities);
                }

                if (work != null)
                {
                    await work(unit);
                }
            });
        }

        #endregion


        #region Links

        private static readonly Dictionary<Tuple<StatUnitTypes, StatUnitTypes>, LinkInfo> LinksMetadata = new[]
        {
            LinkInfo.Create<EnterpriseGroup, EnterpriseUnit>(v => v.EntGroupId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseGroup, LegalUnit>(v => v.EnterpriseGroupRegId, v => v.EnterpriseGroup), 
            LinkInfo.Create<EnterpriseUnit, LegalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit), 
            LinkInfo.Create<EnterpriseUnit, LocalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit), 
            LinkInfo.Create<LegalUnit, LocalUnit>(v => v.LegalUnitId, v => v.LegalUnit), 
        }.ToDictionary(v => Tuple.Create(v.Type1, v.Type2));

        private static readonly Dictionary<StatUnitTypes, List<LinkInfo>> LinksHierarchy =
            LinksMetadata.GroupBy(v => v.Key.Item2, v => v.Value).ToDictionary(v => v.Key, v => v.ToList());

        private static readonly MethodInfo LinkCreateMethod = typeof(StatUnitService).GetMethod(nameof(LinkCreateHandler), BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly MethodInfo LinkDeleteMethod = typeof(StatUnitService).GetMethod(nameof(LinkDeleteHandler), BindingFlags.NonPublic | BindingFlags.Instance);
        private static readonly MethodInfo LinkCanCreateMedthod = typeof(StatUnitService).GetMethod(nameof(LinkCanCreateHandler), BindingFlags.NonPublic | BindingFlags.Instance);

        public async Task LinkDelete(LinkCommentM data)
        {
            await LinkContext(data, LinkDeleteMethod, nameof(Resource.LinkNotExists));
        }

        public async Task LinkCreate(LinkCommentM data)
        {
            await LinkContext(data, LinkCreateMethod,  nameof(Resource.LinkTypeInvalid));
        }

        public async Task<List<UnitLookupVm>> LinksNestedList(UnitLookupVm unit)
        {
            //TODO: Use LinksHierarchy
            var list = new List<UnitLookupVm>();
            switch (unit.Type)
            {
                case StatUnitTypes.EnterpriseGroup:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<EnterpriseUnit>(false)
                            .Where(v => v.EntGroupId == unit.Id).Select(UnitMapping)
                            .Concat(
                                GetUnitsList<LegalUnit>(false)
                                    .Where(v => v.EnterpriseGroupRegId == unit.Id).Select(UnitMapping)
                            ).ToListAsync()
                    ));
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<LegalUnit>(false)
                            .Where(v => v.EnterpriseUnitRegId == unit.Id).Select(UnitMapping)
                            .Concat(
                                GetUnitsList<LocalUnit>(false)
                                    .Where(v => v.EnterpriseUnitRegId == unit.Id).Select(UnitMapping)
                            ).ToListAsync()
                    ));
                    break;
                case StatUnitTypes.LegalUnit:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<LocalUnit>(false)
                            .Where(v => v.LegalUnitId == unit.Id).Select(UnitMapping)
                            .ToListAsync()
                    ));
                    break;
            }
            return list;
        }

        public async Task<List<LinkM>> LinksList(UnitLookupVm root)
        {
            IStatisticalUnit unit;
            switch (root.Type)
            {
                case StatUnitTypes.EnterpriseGroup:
                    unit = await GetUnitById<EnterpriseGroup>(root.Id, false);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unit = await GetUnitById<EnterpriseUnit>(root.Id, false,
                        q => q.Include(v => v.EnterpriseGroup));
                    break;
                case StatUnitTypes.LocalUnit:
                    unit = await GetUnitById<LocalUnit>(root.Id, false,
                        q => q.Include(v => v.EnterpriseUnit).Include(v => v.LegalUnit));
                    break;
                case StatUnitTypes.LegalUnit:
                    unit = await GetUnitById<LegalUnit>(root.Id, false,
                        q => q.Include(v => v.EnterpriseUnit).Include(v => v.EnterpriseGroup));
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }

            var result = new List<LinkM>();

            List<LinkInfo> links;
            var node = ToUnitLookupVm<UnitLookupVm>(unit);

            if (LinksHierarchy.TryGetValue(unit.UnitType, out links))
            {
                links.Select(v => v.Link(unit)).Where(v => v != null).ForEach(v => result.Add(new LinkM()
                {
                    Source1 = ToUnitLookupVm<UnitLookupVm>(v),
                    Source2 = node,
                }));
            }

            var nested = await LinksNestedList(root);
            nested.ForEach(v => result.Add(new LinkM()
            {
                Source1 = node,
                Source2 = v,
            }));

            return result;
        }


        public async Task<bool> LinkCanCreate(LinkM data)
        {
            //TODO: Optimize (Use Include instead of second query + another factory)
            return await LinkContext(data, LinkCanCreateMedthod, nameof(Resource.LinkTypeInvalid));
        }

        public async Task<List<UnitNodeVm>> Search(LinkSearchM search)
        {
            if (search.Source != null && search.Type.HasValue && search.Type != search.Source.Type)
            {
                return new List<UnitNodeVm>();
            }

            var list = new List<IStatisticalUnit>();
            var type = search.Type ?? search.Source?.Type;

            //TODO: Use LinksHierarchy

            if (type == null || type == StatUnitTypes.EnterpriseGroup)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<EnterpriseGroup>(false)
                ).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.EnterpriseUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<EnterpriseUnit>(false)
                        .Include(x => x.EnterpriseGroup)
                ).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LegalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<LegalUnit>(false)
                        .Include(x => x.EnterpriseGroup)
                        .Include(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                ).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LocalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<LocalUnit>(false)
                        .Include(x => x.LegalUnit)
                        .ThenInclude(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                        .Include(x => x.LegalUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                        .Include(x => x.EnterpriseUnit)
                        .ThenInclude(x => x.EnterpriseGroup)
                ).ToListAsync());
            }
            return ToNodeVm(list);
        }

        private IQueryable<T> SearchUnitFilterApply<T>(LinkSearchM search, IQueryable<T> query) where T: IStatisticalUnit
        {
            if (search.Name != null)
            {
                query = query.Where(v => v.Name == search.Name);
            }
            if (search.Source != null)
            {
                query = query.Where(v => v.RegId == search.Source.Id);
            }
            if (search.TurnoverFrom.HasValue)
            {
                query = query.Where(v => v.Turnover >= search.TurnoverFrom.Value);
            }
            if (search.TurnoverTo.HasValue)
            {
                query = query.Where(v => v.Turnover <= search.TurnoverTo.Value);
            }
            if (search.GeographicalCode != null)
            {
                query = query.Where(v => v.Address != null && v.Address.GeographicalCodes == search.GeographicalCode);
            }
            if (search.EmployeesFrom.HasValue)
            {
                query = query.Where(v => v.Employees >= search.EmployeesFrom.Value);
            }
            if (search.EmployeesTo.HasValue)
            {
                query = query.Where(v => v.Employees <= search.EmployeesTo.Value);
            }
            if (search.DataSource != null)
            {
                query = query.Where(v => v.DataSource == search.DataSource);
            }
            return query;
        }

        private List<UnitNodeVm> ToNodeVm(List<IStatisticalUnit> nodes)
        {
            var result = new List<UnitNodeVm>();
            var visited = new Dictionary<Tuple<int, StatUnitTypes>, UnitNodeVm>();
            var stack = new Stack<Tuple<IStatisticalUnit, UnitNodeVm>>();
            foreach (var root in nodes)
            {
                stack.Push(Tuple.Create(root, (UnitNodeVm)null));
            }
            while (stack.Count != 0)
            {
                var pair = stack.Pop();
                var unit = pair.Item1;
                var child = pair.Item2;

                var key = Tuple.Create(unit.RegId, unit.UnitType);
                UnitNodeVm node;
                if (visited.TryGetValue(key, out node))
                {
                    if (child == null)
                    {
                        node.Highlight = true;
                        continue;
                    }
                    if (node.Children == null)
                    {
                        node.Children = new List<UnitNodeVm> {child};
                    }
                    else
                    {
                        if (node.Children.All(v => v.Id != child.Id && v.Type != child.Type))
                        {
                            node.Children.Add(child);
                        }
                    }
                    continue;
                }
                node = ToUnitLookupVm<UnitNodeVm>(unit);
                if (child != null)
                {
                    node.Children = new List<UnitNodeVm> {child};
                }
                else
                {
                    node.Highlight = true;
                }
                visited.Add(key, node);

                List<LinkInfo> links;
                bool isRootNode = true;
                if (LinksHierarchy.TryGetValue(unit.UnitType, out links))
                {
                    foreach (var parentNode in links.Select(v => v.Link(unit)).Where(x => x != null))
                    {
                        isRootNode = false;
                        stack.Push(Tuple.Create(parentNode, node));
                    }
                }
                if (isRootNode)
                {
                    result.Add(node);
                }
            }
            return result;
        }
        
        private async Task<bool> LinkContext<T>(T data, MethodInfo linkMethod, string lookupFailureMessage) where T: LinkM
        {
            LinkInfo info;
            bool reverted = false;
            if (!LinksMetadata.TryGetValue(Tuple.Create(data.Source1.Type, data.Source2.Type), out info))
            {
                if (!LinksMetadata.TryGetValue(Tuple.Create(data.Source2.Type, data.Source1.Type), out info))
                {
                    throw new BadRequestException(lookupFailureMessage);
                }
                reverted = true;
            }

            var method = linkMethod.MakeGenericMethod(
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(info.Type1),
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(info.Type2)
            );
            return await (Task<bool>) method.Invoke(this, new[] {data, reverted, info.Getter, info.Setter});
        }

        private async Task<bool> LinkCanCreateHandler<TParent, TChild>(LinkM data, bool reverted,
            Func<TChild, int?> idGetter, Action<TChild, int?> idSetter) where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
        {
            return await LinkHandler<TParent, TChild, bool>(data, reverted, (unit1, unit2) =>
            {
                var childUnitId = idGetter(unit2);
                return Task.FromResult(childUnitId == null || childUnitId.Value == unit1.RegId);
            });
        }

        private async Task<bool> LinkDeleteHandler<TParent, TChild>(LinkCommentM data, bool reverted,
            Func<TChild, int?> idGetter, Action<TChild, int?> idSetter) where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
        {
            return await LinkHandler<TParent, TChild, bool>(data, reverted, async (unit1, unit2) =>
            {
                var parentId = idGetter(unit2);
                if (!parentId.HasValue || parentId.Value != unit1.RegId)
                {
                    throw new BadRequestException(nameof(Resource.LinkNotExists));
                }
                LinkChangeTrackingHandler(unit2, data.Comment);
                idSetter(unit2, null);
                await _dbContext.SaveChangesAsync();
                return true;
            });
        }

        private async Task<bool> LinkCreateHandler<TParent, TChild>(LinkCommentM data, bool reverted,
            Func<TChild, int?> idGetter, Action<TChild, int?> idSetter) where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
        {
            return await LinkHandler<TParent, TChild, bool>(data, reverted, async (unit1, unit2) =>
            {
                var parentId = idGetter(unit2);

                if (parentId.HasValue)
                {
                    if (parentId == unit1.RegId)
                    {
                        throw new BadRequestException(nameof(Resource.LinkAlreadyExists));
                    }
                    //TODO: Discuss overwrite process throw new BadRequestException(nameof(Resource.LinkUnitAlreadyLinked));
                }
                LinkChangeTrackingHandler(unit2, data.Comment);
                idSetter(unit2, unit1.RegId);
                await _dbContext.SaveChangesAsync();
                return true;
            });
        }

        private async Task<TResult> LinkHandler<TParent, TChild, TResult>(LinkM data, bool reverted, Func<TParent, TChild, Task<TResult>> work)
            where TParent : class, IStatisticalUnit where TChild : class, IStatisticalUnit
        {
            var unit1 = await GetUnitById<TParent>(reverted ? data.Source2.Id : data.Source1.Id, false);
            var unit2 = await GetUnitById<TChild>(reverted ? data.Source1.Id : data.Source2.Id, false);
            return await work(unit1, unit2);
        }

        private List<LinkM> ToLinkModel(IStatisticalUnit parent, IEnumerable<IStatisticalUnit> children)
        {
            var parentVm = ToUnitLookupVm<UnitLookupVm>(parent);
            return children.Select(v => new LinkM()
            {
                Source1 = parentVm,
                Source2 = ToUnitLookupVm<UnitLookupVm>(v),
            }).ToList();
        }

        private void LinkChangeTrackingHandler<TUnit>(TUnit unit, string comment) where TUnit : class, IStatisticalUnit, new()
        {
            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            unit.ChangeReason = ChangeReasons.Edit;
            unit.EditComment = comment;
            _dbContext.Set<TUnit>().Add((TUnit) TrackHistory(unit, hUnit));
        }

        #endregion

        private void AddAddresses(IStatisticalUnit unit, IStatUnitM data)
        {
            if (data.Address != null && !data.Address.IsEmpty())
                unit.Address = GetAddress(data.Address);
            else unit.Address = null;
            if (data.ActualAddress != null && !data.ActualAddress.IsEmpty())
                unit.ActualAddress = data.ActualAddress.Equals(data.Address)
                    ? unit.Address
                    : GetAddress(data.ActualAddress);
            else unit.ActualAddress = null;
        }

        private Address GetAddress(AddressM data)
        {
            return _dbContext.Address.SingleOrDefault(a
                       => a.AddressDetails == data.AddressDetails &&
                          a.GpsCoordinates == data.GpsCoordinates &&
                          a.GeographicalCodes == data.GeographicalCodes) //Check unique fields only
                   ?? new Address()
                   {
                       AddressPart1 = data.AddressPart1,
                       AddressPart2 = data.AddressPart2,
                       AddressPart3 = data.AddressPart3,
                       AddressPart4 = data.AddressPart4,
                       AddressPart5 = data.AddressPart5,
                       AddressDetails = data.AddressDetails,
                       GeographicalCodes = data.GeographicalCodes,
                       GpsCoordinates = data.GpsCoordinates
                   };
        }

        private bool NameAddressIsUnique<T>(string name, AddressM address, AddressM actualAddress)
            where T : class, IStatisticalUnit
        {
            if (address == null) address = new AddressM();
            if (actualAddress == null) actualAddress = new AddressM();
            var units =
                _dbContext.Set<T>()
                    .Include(a => a.Address)
                    .Include(aa => aa.ActualAddress)
                    .Where(u => u.Name == name)
                    .ToList();
            return
                units.All(
                    unit =>
                        !address.Equals(unit.Address) && !actualAddress.Equals(unit.ActualAddress));
        }

        private async Task<IStatisticalUnit> ValidateChanges<T>(IStatUnitM data, int regid)
            where T : class, IStatisticalUnit
        {
            var unit = await GetStatisticalUnitByIdAndType(regid, StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(T)), false);

            if (!unit.Name.Equals(data.Name) &&
                !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.Address != null && data.ActualAddress != null && !data.Address.Equals(unit.Address) &&
                     !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.Address != null && !data.Address.Equals(unit.Address) &&
                     !NameAddressIsUnique<T>(data.Name, data.Address, null))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            else if (data.ActualAddress != null && !data.ActualAddress.Equals(unit.ActualAddress) &&
                     !NameAddressIsUnique<T>(data.Name, null, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            return unit;
        }

        private bool IsNoChanges(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var unitType = unit.GetType();
            var propertyInfo = unitType.GetProperties();
            foreach (var property in propertyInfo)
            {
                var unitProperty = unitType.GetProperty(property.Name).GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name).GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            var statUnit = unit as StatisticalUnit;
            if (statUnit != null)
            {
                var hstatUnit = (StatisticalUnit) hUnit;
                if (!hstatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId))
                {
                    return false;
                }
            }
            return true;
        }

        private static IStatisticalUnit TrackHistory(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var timeStamp = DateTime.Now;
            unit.StartPeriod = timeStamp;
            hUnit.RegId = 0;
            hUnit.EndPeriod = timeStamp;
            hUnit.ParrentId = unit.RegId;
            return hUnit;
        }

        public IEnumerable<LookupVm> GetEnterpriseUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.EnterpriseUnits);

        public IEnumerable<LookupVm> GetEnterpriseGroupsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.EnterpriseGroups);

        public IEnumerable<LookupVm> GetLegalUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.LegalUnits);

        public IEnumerable<LookupVm> GetLocallUnitsLookup() =>
            Mapper.Map<IEnumerable<LookupVm>>(_readCtx.LocalUnits);

        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId)
        {
            var item = id.HasValue
                ? await GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);
            var creator = new StatUnitViewModelCreator();
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return (StatUnitViewModel) creator.Create(item, dataAttributes);
        }

        private static bool HasAccess<T>(ICollection<string> dataAccess, Expression<Func<T, object>> property)
        {
            var name = ExpressionHelper.GetExpressionText(property);
            return dataAccess.Contains($"{typeof(T).Name}.{name}");
        }

        private IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
        {
            var unitType = StatisticalUnitsTypeHelper.GetStatUnitMappingType(type);
            return (IStatisticalUnit) Activator.CreateInstance(unitType);
        }

        private async Task<ISet<string>> InitializeDataAccessAttributes<TModel>(TModel data, string userId,
            StatUnitTypes type) where TModel : IStatUnitM
        {
            var dataAccess = (data.DataAccess ?? Enumerable.Empty<string>()).ToImmutableHashSet();
            var userDataAccess = await _userService.GetDataAccessAttributes(userId, type);
            var dataAccessChanges = dataAccess.Except(userDataAccess);
            if (dataAccessChanges.Count != 0)
            {
                //TODO: Optimize throw only if this field changed
                throw new BadRequestException(nameof(Resource.DataAccessConflict));
            }
            data.DataAccess = dataAccess;
            return dataAccess;
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

        private static T ToUnitLookupVm<T>(Tuple<CodeLookupVm, Type> unit) where T: UnitLookupVm, new()
        {
            var vm = new T()
            {
                Type = StatisticalUnitsTypeHelper.GetStatUnitMappingType(unit.Item2)
            };
            Mapper.Map<CodeLookupVm, UnitLookupVm>(unit.Item1, vm);
            return vm;
        }

        public static T ToUnitLookupVm<T>(IStatisticalUnit unit) where T : UnitLookupVm, new()
        {
            return ToUnitLookupVm<T>(UnitMappingFunc(unit));
        }


        private IEnumerable<UnitLookupVm> ToUnitLookupVm(IEnumerable<Tuple<CodeLookupVm, Type>> source)
        {
            return source.Select(ToUnitLookupVm<UnitLookupVm>);
        }
    }
}
