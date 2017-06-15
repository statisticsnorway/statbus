using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Core;
using nscreg.Server.Models.StatUnits;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Threading.Tasks;
using nscreg.Data.Helpers;
using nscreg.Resources.Languages;
using nscreg.Server.Models;
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
        private readonly NSCRegDbContext _dbContext;
        private readonly ReadContext _readCtx;
        private readonly UserService _userService;

        private static readonly Expression<Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>>> UnitMapping =
            u => Tuple.Create(
                new CodeLookupVm {Id = u.RegId, Code = u.StatId, Name = u.Name},
                u.GetType());

        private static readonly Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>> UnitMappingFunc =
            UnitMapping.Compile();

        public StatUnitService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _readCtx = new ReadContext(dbContext);
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

        private async Task<IEnumerable<object>> FetchUnitHistoryAsync<T>(int id)
            where T : class, IStatisticalUnit
            => await _dbContext.Set<T>()
                .Join(
                    _dbContext.Users,
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

        private static readonly MethodInfo LinkCreateMethod =
            typeof(StatUnitService).GetMethod(nameof(LinkCreateHandler), BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkDeleteMethod =
            typeof(StatUnitService).GetMethod(nameof(LinkDeleteHandler), BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkCanCreateMedthod =
            typeof(StatUnitService).GetMethod(nameof(LinkCanCreateHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        public async Task LinkDelete(LinkCommentM data)
        {
            await LinkContext(data, LinkDeleteMethod, nameof(Resource.LinkNotExists));
        }

        public async Task LinkCreate(LinkCommentM data)
        {
            await LinkContext(data, LinkCreateMethod, nameof(Resource.LinkTypeInvalid));
        }

        public async Task<List<UnitLookupVm>> LinksNestedList(IUnitVm unit)
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

        public async Task<List<LinkM>> LinksList(IUnitVm root)
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


        public async Task<bool> LinkCanCreate(LinkSubmitM data)
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

        private IQueryable<T> SearchUnitFilterApply<T>(LinkSearchM search, IQueryable<T> query)
            where T : IStatisticalUnit
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
                stack.Push(Tuple.Create(root, (UnitNodeVm) null));
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
                    foreach (
                        var parentNode in
                        links.Select(v => v.Link(unit))
                            .Where(x => x != null && x.ParrentId == null && x.IsDeleted == false))
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

        private async Task<bool> LinkContext<T>(T data, MethodInfo linkMethod, string lookupFailureMessage)
            where T : LinkSubmitM
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

        private async Task<bool> LinkCanCreateHandler<TParent, TChild>(LinkSubmitM data, bool reverted,
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

        private async Task<TResult> LinkHandler<TParent, TChild, TResult>(LinkSubmitM data, bool reverted,
            Func<TParent, TChild, Task<TResult>> work)
            where TParent : class, IStatisticalUnit where TChild : class, IStatisticalUnit
        {
            var unit1 = await GetUnitById<TParent>(reverted ? data.Source2.Id : data.Source1.Id, false);
            var unit2 = await GetUnitById<TChild>(reverted ? data.Source1.Id : data.Source2.Id, false);
            return await work(unit1, unit2);
        }

        private void LinkChangeTrackingHandler<TUnit>(TUnit unit, string comment)
            where TUnit : class, IStatisticalUnit, new()
        {
            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            unit.ChangeReason = ChangeReasons.Edit;
            unit.EditComment = comment;
            _dbContext.Set<TUnit>().Add((TUnit) TrackHistory(unit, hUnit));
        }

        #endregion

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

        private IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
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

        private static T ToUnitLookupVm<T>(Tuple<CodeLookupVm, Type> unit) where T : UnitLookupVm, new()
        {
            var vm = new T
            {
                Type = StatisticalUnitsTypeHelper.GetStatUnitMappingType(unit.Item2)
            };
            Mapper.Map<CodeLookupVm, UnitLookupVm>(unit.Item1, vm);
            return vm;
        }

        private static T ToUnitLookupVm<T>(IStatisticalUnit unit) where T : UnitLookupVm, new()
        {
            return ToUnitLookupVm<T>(UnitMappingFunc(unit));
        }

        private IEnumerable<UnitLookupVm> ToUnitLookupVm(IEnumerable<Tuple<CodeLookupVm, Type>> source)
        {
            return source.Select(ToUnitLookupVm<UnitLookupVm>);
        }

        public async Task<SearchVm<InconsistentRecord>> GetInconsistentRecordsAsync(PaginationModel model)
        {
            var validator = new InconsistentRecordValidator();
            var units =
                _readCtx.StatUnits.Where(x => !x.IsDeleted && x.ParrentId == null)
                    .Select(x => validator.Specify(x))
                    .Where(x => x.Inconsistents.Count > 0);
            var groups = _readCtx.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParrentId == null)
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
    }
}
