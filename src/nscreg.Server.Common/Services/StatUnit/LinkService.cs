using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Links;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Class communication service stat. units
    /// </summary>
    public class LinkService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly CommonService _commonSvc;
        private readonly UserService _userService;
        private readonly ElasticService _elasticService;
        private readonly IMapper _mapper;

        public LinkService(NSCRegDbContext dbContext, IMapper mapper /*CommonService commonSvc, IElasticUpsertService elasticService, IUserService userService*/)
        {
            _dbContext = dbContext;
            _mapper = mapper;
            _commonSvc = new CommonService(dbContext, mapper);
            _elasticService = new ElasticService(dbContext, mapper);
            _userService = new UserService(dbContext, mapper);
        }

        /// <summary>
        /// Unlink method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task LinkDelete(LinkCommentM data, string userId)
            => await LinkContext(data, LinkDeleteMethod, nameof(Resource.LinkNotExists), userId);

        /// <summary>
        /// Connection creation method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task LinkCreate(LinkCommentM data, string userId)
            => await LinkContext(data, LinkCreateMethod, nameof(Resource.LinkTypeInvalid), userId);

        /// <summary>
        /// Method for obtaining a list of links
        /// </summary>
        /// <param name = "root"> Root node </param>
        /// <returns> </returns>
        public async Task<List<LinkM>> LinksList(IUnitVm root)
        {
            IStatisticalUnit unit;
            switch (root.Type)
            {
                case StatUnitTypes.EnterpriseGroup:
                    unit = await _commonSvc.GetUnitById<EnterpriseGroup>(root.Id, false);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unit = await _commonSvc.GetUnitById<EnterpriseUnit>(root.Id, false,
                        q => q.Include(v => v.EnterpriseGroup));
                    break;
                case StatUnitTypes.LocalUnit:
                    unit = await _commonSvc.GetUnitById<LocalUnit>(root.Id, false,
                        q => q.Include(v => v.LegalUnit));
                    break;
                case StatUnitTypes.LegalUnit:
                    unit = await _commonSvc.GetUnitById<LegalUnit>(root.Id, false,
                        q => q.Include(v => v.EnterpriseUnit));
                    break;
                default:
                    throw new ArgumentOutOfRangeException();
            }

            var result = new List<LinkM>();

            List<LinkInfo> links;
            var node = _commonSvc.ToUnitLookupVm<UnitLookupVm>(unit);

            if (LinksHierarchy.TryGetValue(unit.UnitType, out links))
            {
                links.Select(v => v.Link(unit)).Where(v => v != null).ForEach(v => result.Add(new LinkM
                {
                    Source1 = _commonSvc.ToUnitLookupVm<UnitLookupVm>(v),
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

        /// <summary>
        /// Method for getting a nested list of links
        /// </summary>
        /// <param name = "unit"> </param>
        /// <returns> </returns>
        public async Task<List<UnitLookupVm>> LinksNestedList(IUnitVm unit)
        {
            // TODO: Use LinksHierarchy
            var list = new List<UnitLookupVm>();
            switch (unit.Type)
            {
                case StatUnitTypes.EnterpriseGroup:
                    list.AddRange(_commonSvc.ToUnitLookupVm(
                        await _commonSvc.GetUnitsList<EnterpriseUnit>(false)
                            .Where(v => v.EntGroupId == unit.Id && v.UnitStatusId == 7).Select(CommonService.UnitMapping)
                            .ToListAsync()
                    ));
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    list.AddRange(_commonSvc.ToUnitLookupVm(
                        await _commonSvc.GetUnitsList<LegalUnit>(false)
                            .Where(v => v.EnterpriseUnitRegId == unit.Id && v.UnitStatusId == 7).Select(CommonService.UnitMapping)
                            .ToListAsync()
                    ));
                    break;
                case StatUnitTypes.LegalUnit:
                    list.AddRange(_commonSvc.ToUnitLookupVm(
                        await _commonSvc.GetUnitsList<LocalUnit>(false)
                            .Where(v => v.LegalUnitId == unit.Id && v.UnitStatusId == 7).Select(CommonService.UnitMapping)
                            .ToListAsync()
                    ));
                    break;
            }
            return list;
        }

        // TODO: Optimize (Use Include instead of second query + another factory)
        /// <summary>
        /// The method of checking for the possibility of being connected
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        public async Task<bool> LinkCanCreate(LinkSubmitM data, string userId)
            => await LinkContext(data, LinkCanCreateMedthod, nameof(Resource.LinkTypeInvalid), userId);

        /// <summary>
        /// Connection search method
        /// </summary>
        /// <param name = "search"> Link search model </param>
        /// <param name = "userId"> user ID </param>
        /// <returns> </returns>
        public async Task<List<UnitNodeVm>> Search(LinkSearchM search, string userId)
        {
            var searchModel = new SearchQueryM()
            {
                Name = search.Wildcard,
                Type = search.Type != null
                    ? new List<StatUnitTypes> { (StatUnitTypes)search.Type }
                    : new List<StatUnitTypes>(),
                RegId = search.Id,
                RegionId = search.RegionCode,
                LastChangeFrom = search.LastChangeFrom,
                LastChangeTo = search.LastChangeTo,
                DataSourceClassificationId = search.DataSourceClassificationId,
                PageSize = 20
            };
            var searchResponse = await _elasticService.Search(searchModel, userId, false);
            var units = searchResponse.Result.ToList();
            var list = new List<IStatisticalUnit>();
            var listIds = units.Select(x => x.RegId).ToList();
            var type = search.Type;
            if (type == null || type == StatUnitTypes.EnterpriseGroup)
            {
                var entGroup = _commonSvc.GetUnitsList<EnterpriseGroup>(false)
                    .Where(x => listIds.Contains(x.RegId))
                    .Include(x => x.EnterpriseUnits)
                    .ThenInclude(x => x.LegalUnits)
                    .ThenInclude(x => x.LocalUnits);
                list.AddRange(entGroup);
                list.AddRange(entGroup.SelectMany(x => x.EnterpriseUnits.Where(y => y.IsDeleted == false)));
                list.AddRange(entGroup.SelectMany(x => x.EnterpriseUnits.Where(y => y.IsDeleted == false).SelectMany(y => y.LegalUnits.Where(z => z.IsDeleted == false))));
                list.AddRange(entGroup.SelectMany(x => x.EnterpriseUnits.Where(y => y.IsDeleted == false).SelectMany(y => y.LegalUnits.Where(z => z.IsDeleted == false).SelectMany(z => z.LocalUnits.Where(l => l.IsDeleted == false)))));
            }

            if (type == null || type == StatUnitTypes.EnterpriseUnit)
            {
                var entUnit = _commonSvc.GetUnitsList<EnterpriseUnit>(false)
                    .Where(x => listIds.Contains(x.RegId))
                    .Include(x => x.LegalUnits)
                    .ThenInclude(x => x.LocalUnits)
                    .Include(x => x.EnterpriseGroup).AsSplitQuery();

                list.AddRange(entUnit.Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .Select(x => x.EnterpriseGroup));

                list.AddRange(entUnit
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits.Where(c => c.IsDeleted == false)));

                list.AddRange(entUnit
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits.Where(c => c.IsDeleted == false)
                        .SelectMany(c => c.LegalUnits.Where(z => z.IsDeleted == false))));

                list.AddRange(entUnit.Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits.Where(c => c.IsDeleted == false)
                        .SelectMany(c => c.LegalUnits.Where(z => z.IsDeleted == false)
                            .SelectMany(y => y.LocalUnits.Where(j => j.IsDeleted == false)))));

                list.AddRange(entUnit);
                list.AddRange(entUnit.SelectMany(x=>x.LegalUnits.Where(y => y.IsDeleted == false)));
                list.AddRange(entUnit.SelectMany(x=>x.LegalUnits.Where(y => y.IsDeleted == false).SelectMany(y=>y.LocalUnits.Where(z => z.IsDeleted == false))));
            }

            if (type == null || type == StatUnitTypes.LegalUnit)
            {
                var legalUnit = _commonSvc.GetUnitsList<LegalUnit>(false)
                    .Where(x => listIds.Contains(x.RegId))
                    .Include(x => x.EnterpriseUnit)
                    .ThenInclude(x => x.EnterpriseGroup)
                    .Include(x => x.LocalUnits);

                
                list.AddRange(legalUnit.Where(x => x.EnterpriseUnit.IsDeleted == false).Select(x => x.EnterpriseUnit).Where(x => x.EnterpriseGroup.IsDeleted == false).Select(x => x.EnterpriseGroup));

                list.AddRange(legalUnit.Where(x => !x.EnterpriseUnit.IsDeleted)
                    .SelectMany(x => x.EnterpriseUnit.EnterpriseGroup.EnterpriseUnits.Where(z => !z.IsDeleted)));

                list.AddRange(legalUnit
                    .Where(x => !x.EnterpriseUnit.IsDeleted)
                    .SelectMany(x => x.EnterpriseUnit.EnterpriseGroup.EnterpriseUnits.Where(c => c.IsDeleted == false))
                    .SelectMany(c => c.LegalUnits.Where(x => x.IsDeleted == false)));

                list.AddRange(legalUnit
                    .Where(x => !x.EnterpriseUnit.IsDeleted)
                    .SelectMany(x => x.EnterpriseUnit.EnterpriseGroup.EnterpriseUnits.Where(c => c.IsDeleted == false))
                    .SelectMany(c => c.LegalUnits.Where(x => x.IsDeleted == false))
                    .SelectMany(z => z.LocalUnits.Where(x => x.IsDeleted == false)));

                list.AddRange(legalUnit);
                list.AddRange(legalUnit.SelectMany(x => x.LocalUnits.Where(y => y.IsDeleted == false)));
            }

            if (type == null || type == StatUnitTypes.LocalUnit)
            {
                var localUnit = _commonSvc.GetUnitsList<LocalUnit>(false)
                    .Where(x => listIds.Contains(x.RegId))
                    .Include(x => x.LegalUnit)
                    .ThenInclude(x => x.EnterpriseUnit)
                    .ThenInclude(x => x.EnterpriseGroup);

                list.AddRange(localUnit
                    .Where(x => x.LegalUnit.IsDeleted == false)
                    .Select(x => x.LegalUnit)
                    .Where(x => x.EnterpriseUnit.IsDeleted == false)
                    .Select(x => x.EnterpriseUnit)
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .Select(x => x.EnterpriseGroup));

                list.AddRange(localUnit
                    .Where(x => x.LegalUnit.IsDeleted == false)
                    .Select(x => x.LegalUnit)
                    .Where(x => x.EnterpriseUnit.IsDeleted == false)
                    .Select(x => x.EnterpriseUnit)
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits
                        .Where(c => c.IsDeleted == false)));

                list.AddRange(localUnit
                    .Where(x => x.LegalUnit.IsDeleted == false)
                    .Select(x => x.LegalUnit)
                    .Where(x => x.EnterpriseUnit.IsDeleted == false)
                    .Select(x => x.EnterpriseUnit)
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits
                        .Where(c => c.IsDeleted == false)
                        .SelectMany(z => z.LegalUnits
                            .Where(c => c.IsDeleted == false))));

                list.AddRange(localUnit
                    .Where(x => x.LegalUnit.IsDeleted == false)
                    .Select(x => x.LegalUnit)
                    .Where(x => x.EnterpriseUnit.IsDeleted == false)
                    .Select(x => x.EnterpriseUnit)
                    .Where(x => x.EnterpriseGroup.IsDeleted == false)
                    .SelectMany(x => x.EnterpriseGroup.EnterpriseUnits
                        .Where(c => c.IsDeleted == false)
                        .SelectMany(z => z.LegalUnits
                            .Where(c => c.IsDeleted == false)
                            .SelectMany(j => j.LocalUnits
                                .Where(c => c.IsDeleted == false)))));

                list.AddRange(localUnit.Where(x => x.LegalUnit.IsDeleted == false).Select(x => x.LegalUnit));
                list.AddRange(localUnit);
            }

            return ToNodeVm(list, listIds);
        }

        /// <summary>
        /// Method for obtaining link metadata
        /// </summary>
        private static readonly Dictionary<Tuple<StatUnitTypes, StatUnitTypes>, LinkInfo> LinksMetadata = new[]
        {
            LinkInfo.Create<EnterpriseGroup, EnterpriseUnit>(v => v.EntGroupId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseUnit, LegalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit),
            LinkInfo.Create<LegalUnit, LocalUnit>(v => v.LegalUnitId, v => v.LegalUnit),
        }.ToDictionary(v => Tuple.Create(v.Type1, v.Type2));

        /// <summary>
        /// Method for obtaining hierarchy metadata
        /// </summary>
        private static readonly Dictionary<StatUnitTypes, List<LinkInfo>> LinksHierarchy =
            LinksMetadata
                .GroupBy(v => v.Key.Item2, v => v.Value)
                .ToDictionary(v => v.Key, v => v.ToList());

        /// <summary>
        /// Method handler unlink
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "reverted"> Reverse </param>
        /// <param name = "idGetter"> Id getter </param>
        /// <param name = "idSetter"> Id setter </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        private async Task<bool> LinkDeleteHandler<TParent, TChild>(
            LinkCommentM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter,
            string userId)
            where TParent : class, IStatisticalUnit, new()
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

                    var changeDateTime = DateTime.Now;
                    _commonSvc.TrackUnitHistoryFor<TChild>(unit2.RegId, userId, ChangeReasons.Edit, data.Comment, changeDateTime);

                    idSetter(unit2, null);

                    _commonSvc.TrackUnitHistoryFor<TParent>(unit1.RegId, userId, ChangeReasons.Edit, data.Comment, changeDateTime);

                    using (var transaction = _dbContext.Database.BeginTransaction())
                    {
                        try
                        {
                            await _dbContext.SaveChangesAsync();
                            transaction.Commit();
                            return true;
                        }
                        catch (Exception e)
                        {
                            throw new BadRequestException(nameof(Resource.SaveError), e);
                        }

                    }
                });

        /// <summary>
        /// Method for creating a connection
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "reverted"> Reverse </param>
        /// <param name = "idGetter"> Id getter </param>
        /// <param name = "idSetter"> Id setter </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        private async Task<bool> LinkCreateHandler<TParent, TChild>(
            LinkCommentM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter,
            string userId)
            where TParent : class, IStatisticalUnit, new()
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

                    var changeDateTime = DateTime.Now;
                    _commonSvc.TrackUnitHistoryFor<TChild>(unit2.RegId, userId, ChangeReasons.Edit, data.Comment, changeDateTime);

                    idSetter(unit2, unit1.RegId);

                    _commonSvc.TrackUnitHistoryFor<TParent>(unit1.RegId, userId, ChangeReasons.Edit, data.Comment, changeDateTime);

                    using (var transaction = _dbContext.Database.BeginTransaction())
                    {
                        try
                        {
                            await _dbContext.SaveChangesAsync();
                            transaction.Commit();
                            return true;
                        }
                        catch (Exception e)
                        {
                            throw new BadRequestException(nameof(Resource.SaveError), e);
                        }

                    }

                });

        /// <summary>
        /// Communication handler method for being created
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "reverted"> Reverse </param>
        /// <param name = "idGetter"> Id getter </param>
        /// <returns> </returns>
        private async Task<bool> LinkCanCreateHandler<TParent, TChild>(
            LinkSubmitM data,
            bool reverted,
            Func<TChild, int?> idGetter,
            Action<TChild, int?> idSetter,
            string userId)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit, new()
            => await LinkHandler<TParent, TChild, bool>(data, reverted, (unit1, unit2) =>
            {
                var childUnitId = idGetter(unit2);
                return Task.FromResult(childUnitId == null || childUnitId.Value == unit1.RegId);
            });

        /// <summary>
        /// Communication handler method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "reverted"> Reverse </param>
        /// <param name = "work"> At work </param>
        /// <returns> </returns>
        private async Task<TResult> LinkHandler<TParent, TChild, TResult>(
            LinkSubmitM data,
            bool reverted,
            Func<TParent, TChild, Task<TResult>> work)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit
            => await work(
                await _commonSvc.GetUnitById<TParent>(reverted ? data.Source2.Id : data.Source1.Id, false),
                await _commonSvc.GetUnitById<TChild>(reverted ? data.Source1.Id : data.Source2.Id, false));

        private static readonly MethodInfo LinkCreateMethod =
            typeof(LinkService).GetMethod(nameof(LinkCreateHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkDeleteMethod =
            typeof(LinkService).GetMethod(nameof(LinkDeleteHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        private static readonly MethodInfo LinkCanCreateMedthod =
            typeof(LinkService).GetMethod(nameof(LinkCanCreateHandler),
                BindingFlags.NonPublic | BindingFlags.Instance);

        /// <summary>
        /// Communication context check method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "linkMethod"> Communication method </param>
        /// <param name = "lookupFailureMessage"> Search error message </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        private async Task<bool> LinkContext<T>(T data, MethodInfo linkMethod, string lookupFailureMessage, string userId)
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
            return await (Task<bool>)method.Invoke(this, new[] { data, reverted, info.Getter, info.Setter, userId });
        }

        /// <summary>
        /// Method for converting a node to a view model
        /// </summary>
        /// <param name = "nodes"> Nodes </param>
        /// <returns> </returns>
        private List<UnitNodeVm> ToNodeVm(List<IStatisticalUnit> nodes, List<int> listIds)
        {
            var result = new List<UnitNodeVm>();
            var visited = new Dictionary<Tuple<int, StatUnitTypes>, UnitNodeVm>();
            var stack = new Stack<Tuple<IStatisticalUnit, UnitNodeVm>>();
            foreach (var root in nodes)
            {
                if (root != null)
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
                        continue;
                    }
                    if (node.Children == null)
                    {
                        node.Children = new List<UnitNodeVm> { child };
                    }
                    else
                    {
                        if (node.Children.All(v => v.Id != child.Id && v.Type != child.Type))
                        {
                            node.Children.Add(child);
                        }

                        if (node.Children.All(v => v.Id != child.Id && v.Type == child.Type))
                        {
                            node.Children.Add(child);
                        }
                    }
                    continue;
                }
                node = _commonSvc.ToUnitLookupVm<UnitNodeVm>(unit);
                if (child != null)
                {
                    node.Children = new List<UnitNodeVm> { child };
                }
                if (listIds.Contains(unit.RegId))
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
                            .Where(x => x != null && x.IsDeleted == false))
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
