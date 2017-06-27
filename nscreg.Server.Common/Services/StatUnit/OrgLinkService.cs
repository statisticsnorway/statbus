using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Links;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class OrgLinkService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly Common _commonSvc;

        public OrgLinkService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _commonSvc = new Common(dbContext);
        }


        public async Task<List<UnitNodeVm>> GetAllOrgLinks(LinkSearchM search)
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
                list.AddRange(
                    await SearchUnitFilterApply(search, _commonSvc.GetUnitsList<EnterpriseGroup>(false)).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.EnterpriseUnit)
            {
                list.AddRange(
                    await SearchUnitFilterApply(search,
                        _commonSvc.GetUnitsList<EnterpriseUnit>(false).Include(x => x.EnterpriseGroup)).ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LegalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                        search,
                        _commonSvc.GetUnitsList<LegalUnit>(false)
                            .Include(x => x.EnterpriseGroup)
                            .Include(x => x.EnterpriseUnit)
                            .ThenInclude(x => x.EnterpriseGroup))
                    .ToListAsync());
            }

            if (type == null || type == StatUnitTypes.LocalUnit)
            {
                list.AddRange(await SearchUnitFilterApply(
                        search,
                        _commonSvc.GetUnitsList<LocalUnit>(false)
                            .Include(x => x.LegalUnit)
                            .ThenInclude(x => x.EnterpriseUnit)
                            .ThenInclude(x => x.EnterpriseGroup)
                            .Include(x => x.LegalUnit)
                            .ThenInclude(x => x.EnterpriseGroup)
                            .Include(x => x.EnterpriseUnit)
                            .ThenInclude(x => x.EnterpriseGroup))
                    .ToListAsync());
            }
            return ToNodeVm(list);
        }

        private static IQueryable<T> SearchUnitFilterApply<T>(LinkSearchM search, IQueryable<T> query)
        where T : IStatisticalUnit
        => query.Where(x => (search.Name == null || x.Name == search.Name)
                        && (search.Source == null || x.RegId == search.Source.Id)
                        && (search.TurnoverFrom == null || x.Turnover >= search.TurnoverFrom.Value)
                        && (search.TurnoverTo == null || x.Turnover <= search.TurnoverTo)
                        && (search.EmployeesFrom == null || x.Employees >= search.EmployeesFrom.Value)
                        && (search.EmployeesTo == null || x.Employees <= search.EmployeesTo.Value)
                        && (search.DataSource == null || x.DataSource == search.DataSource));

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
                        node.Children = new List<UnitNodeVm> { child };
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
                node = Common.ToUnitLookupVm<UnitNodeVm>(unit);
                if (child != null)
                {
                    node.Children = new List<UnitNodeVm> { child };
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

        private static readonly Dictionary<StatUnitTypes, List<LinkInfo>> LinksHierarchy =
        LinksMetadata
        .GroupBy(v => v.Key.Item2, v => v.Value)
        .ToDictionary(v => v.Key, v => v.ToList());

        private static readonly Dictionary<Tuple<StatUnitTypes, StatUnitTypes>, LinkInfo> LinksMetadata = new[]
{
            LinkInfo.Create<EnterpriseGroup, EnterpriseUnit>(v => v.EntGroupId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseGroup, LegalUnit>(v => v.EnterpriseGroupRegId, v => v.EnterpriseGroup),
            LinkInfo.Create<EnterpriseUnit, LegalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit),
            LinkInfo.Create<EnterpriseUnit, LocalUnit>(v => v.EnterpriseUnitRegId, v => v.EnterpriseUnit),
            LinkInfo.Create<LegalUnit, LocalUnit>(v => v.LegalUnitId, v => v.LegalUnit),
        }.ToDictionary(v => Tuple.Create(v.Type1, v.Type2));

    }
}
