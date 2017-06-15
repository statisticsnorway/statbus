using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Helpers;
using nscreg.Resources.Languages;
using nscreg.Server.Core;
using nscreg.Server.Models.Links;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.StatUnits;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using static nscreg.Server.Services.StatUnit.Common;

namespace nscreg.Server.Services.StatUnit
{
    public class LinkService
    {
        private readonly NSCRegDbContext _dbContext;

        public LinkService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task LinkDelete(LinkCommentM data)
            => await LinkContext(data, LinkDeleteMethod, nameof(Resource.LinkNotExists));

        public async Task LinkCreate(LinkCommentM data)
            => await LinkContext(data, LinkCreateMethod, nameof(Resource.LinkTypeInvalid));

        public async Task<List<UnitLookupVm>> LinksNestedList(IUnitVm unit)
        {
            // TODO: Use LinksHierarchy
            var list = new List<UnitLookupVm>();
            switch (unit.Type)
            {
                case StatUnitTypes.EnterpriseGroup:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<EnterpriseUnit>(_dbContext, false)
                            .Where(v => v.EntGroupId == unit.Id).Select(UnitMapping)
                            .Concat(
                                GetUnitsList<LegalUnit>(_dbContext, false)
                                    .Where(v => v.EnterpriseGroupRegId == unit.Id).Select(UnitMapping)
                            ).ToListAsync()
                    ));
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<LegalUnit>(_dbContext, false)
                            .Where(v => v.EnterpriseUnitRegId == unit.Id).Select(UnitMapping)
                            .Concat(
                                GetUnitsList<LocalUnit>(_dbContext, false)
                                    .Where(v => v.EnterpriseUnitRegId == unit.Id).Select(UnitMapping)
                            ).ToListAsync()
                    ));
                    break;
                case StatUnitTypes.LegalUnit:
                    list.AddRange(ToUnitLookupVm(
                        await GetUnitsList<LocalUnit>(_dbContext, false)
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
                    unit = await GetUnitById<EnterpriseGroup>(_dbContext, root.Id, false);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unit = await GetUnitById<EnterpriseUnit>(_dbContext, root.Id, false,
                        q => q.Include(v => v.EnterpriseGroup));
                    break;
                case StatUnitTypes.LocalUnit:
                    unit = await GetUnitById<LocalUnit>(_dbContext, root.Id, false,
                        q => q.Include(v => v.EnterpriseUnit).Include(v => v.LegalUnit));
                    break;
                case StatUnitTypes.LegalUnit:
                    unit = await GetUnitById<LegalUnit>(_dbContext, root.Id, false,
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
                links.Select(v => v.Link(unit)).Where(v => v != null).ForEach(v => result.Add(new LinkM
                {
                    Source1 = ToUnitLookupVm<UnitLookupVm>(v),
                    Source2 = node,
                }));
            }

            var nested = await LinksNestedList(root);
            nested.ForEach(v => result.Add(new LinkM
            {
                Source1 = node,
                Source2 = v,
            }));

            return result;
        }

        //TODO: Optimize (Use Include instead of second query + another factory)
        public async Task<bool> LinkCanCreate(LinkSubmitM data)
            => await LinkContext(data, LinkCanCreateMedthod, nameof(Resource.LinkTypeInvalid));

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
                    GetUnitsList<EnterpriseGroup>(_dbContext, false)
                ).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.EnterpriseUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<EnterpriseUnit>(_dbContext, false)
                        .Include(x => x.EnterpriseGroup)
                ).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LegalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                        search,
                        GetUnitsList<LegalUnit>(_dbContext, false)
                            .Include(x => x.EnterpriseGroup)
                            .Include(x => x.EnterpriseUnit)
                            .ThenInclude(x => x.EnterpriseGroup))
                    .ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LocalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                    search,
                    GetUnitsList<LocalUnit>(_dbContext, false)
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

        private static IQueryable<T> SearchUnitFilterApply<T>(LinkSearchM search, IQueryable<T> query)
            where T : IStatisticalUnit
            => query.Where(x => (search.Name == null || x.Name == search.Name)
                                && (search.Source == null || x.RegId == search.Source.Id)
                                && (search.TurnoverFrom == null || x.Turnover >= search.TurnoverFrom.Value)
                                && (search.TurnoverTo == null || x.Turnover <= search.TurnoverTo)
                                && (search.GeographicalCode == null || x.Address != null
                                    && x.Address.GeographicalCodes == search.GeographicalCode)
                                && (search.EmployeesFrom == null || x.Employees >= search.EmployeesFrom.Value)
                                && (search.EmployeesTo == null || x.Employees <= search.EmployeesTo.Value)
                                && (search.DataSource == null || x.DataSource == search.DataSource));

        private void LinkChangeTrackingHandler<TUnit>(TUnit unit, string comment)
            where TUnit : class, IStatisticalUnit, new()
        {
            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            unit.ChangeReason = ChangeReasons.Edit;
            unit.EditComment = comment;
            _dbContext.Set<TUnit>().Add((TUnit) TrackHistory(unit, hUnit));
        }

        private static readonly Dictionary<Tuple<StatUnitTypes, StatUnitTypes>, LinkInfo> LinksMetadata = new[]
        {
            LinkInfo.Create<EnterpriseGroup, EnterpriseUnit>(v => v.EntGroupId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseGroup, LegalUnit>(v => v.EnterpriseGroupRegId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseUnit, LegalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit),
            LinkInfo.Create<EnterpriseUnit, LocalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit),
            LinkInfo.Create<LegalUnit, LocalUnit>(v => v.LegalUnitId, v => v.LegalUnit),
        }.ToDictionary(v => Tuple.Create(v.Type1, v.Type2));

        private static readonly Dictionary<StatUnitTypes, List<LinkInfo>> LinksHierarchy =
            LinksMetadata
                .GroupBy(v => v.Key.Item2, v => v.Value)
                .ToDictionary(v => v.Key, v => v.ToList());

        private async Task<bool> LinkDeleteHandler<TParent, TChild>(
            LinkCommentM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
            => await LinkHandler<TParent, TChild, bool>(
                data,
                reverted,
                async (unit1, unit2) =>
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

        private async Task<bool> LinkCreateHandler<TParent, TChild>(
            LinkCommentM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
            => await LinkHandler<TParent, TChild, bool>(
                data,
                reverted,
                async (unit1, unit2) =>
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

        private async Task<bool> LinkCanCreateHandler<TParent, TChild>(
            LinkSubmitM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
            => await LinkHandler<TParent, TChild, bool>(data, reverted, (unit1, unit2) =>
            {
                var childUnitId = idGetter(unit2);
                return Task.FromResult(childUnitId == null || childUnitId.Value == unit1.RegId);
            });

        private async Task<TResult> LinkHandler<TParent, TChild, TResult>(
            LinkSubmitM data,
            bool reverted,
            Func<TParent, TChild, Task<TResult>> work)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit
            => await work(
                await GetUnitById<TParent>(_dbContext, reverted ? data.Source2.Id : data.Source1.Id, false),
                await GetUnitById<TChild>(_dbContext, reverted ? data.Source1.Id : data.Source2.Id, false));

        private static readonly MethodInfo LinkCreateMethod =
            typeof(LinkService).GetMethod(nameof(LinkCreateHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkDeleteMethod =
            typeof(LinkService).GetMethod(nameof(LinkDeleteHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkCanCreateMedthod =
            typeof(LinkService).GetMethod(nameof(LinkCanCreateHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        private async Task<bool> LinkContext<T>(T data, MethodInfo linkMethod, string lookupFailureMessage)
            where T : LinkSubmitM
        {
            LinkInfo info;
            var reverted = false;
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
                var isRootNode = true;
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
    }
}
