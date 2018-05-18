using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Server.Common.Services.SampleFrames
{
    internal class SampleFrameExecutor
    {
        private readonly NSCRegDbContext _context;
        private readonly ExpressionTreeParser<EnterpriseGroup> _enterpriseGroupExprParser;
        private readonly ExpressionTreeParser<StatisticalUnit> _statUnitExprParser;
        private readonly PropertyValuesProvider _propertyValuesProvider;

        public SampleFrameExecutor(NSCRegDbContext context)
        {
            _context = context;
            _statUnitExprParser = new ExpressionTreeParser<StatisticalUnit>(context);
            _enterpriseGroupExprParser = new ExpressionTreeParser<EnterpriseGroup>(context);
            _propertyValuesProvider = new PropertyValuesProvider(context);
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Execute(ExpressionGroup tree,
            List<FieldEnum> fields, int? count = null)
        {
            var units = await ExecuteSampleFrameOnStatUnits(count, tree, fields);
            var groups = await ExecuteSampleFrameOnEnterpriseGroupsAsync(count - units.Count, tree, fields);

            return units.Concat(groups).Select(unit =>
                fields.ToDictionary(field => field, field => _propertyValuesProvider.GetValue(unit, field)));
        }

        private IQueryable<StatisticalUnit> GetQueryForUnits(IEnumerable<FieldEnum> fields)
        {
            var query = _context.StatisticalUnits.AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.ActivityCodes) || fieldLookup.Contains(FieldEnum.MainActivity))
                query = query.Include(x => x.ActivitiesUnits)
                    .ThenInclude(x => x.Activity)
                    .ThenInclude(x => x.ActivityCategory);

            if (fieldLookup.Contains(FieldEnum.Region) || fieldLookup.Contains(FieldEnum.ActualAddress))
                query = query.Include(x => x.Address)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.InstSectorCodeId))
                query = query.Include(x => x.InstSectorCode);

            if (fieldLookup.Contains(FieldEnum.LegalForm))
                query = query.Include(x => x.LegalForm);

            if (fieldLookup.Contains(FieldEnum.ContactPerson))
                query = query.Include(x => x.PersonsUnits)
                    .ThenInclude(x => x.Person);

            return query;
        }

        private async Task<List<IStatisticalUnit>> ExecuteSampleFrameOnEnterpriseGroupsAsync(int? count, ExpressionGroup expressionGroup, IEnumerable<FieldEnum> fields)
        {
            var predicate = _enterpriseGroupExprParser.Parse(expressionGroup);
            var entQuery = GetQueryForEnterpriseGroups(fields);

            var query = entQuery
                .Where(predicate);
            if (count.HasValue)
                query = query.Take(count.Value);
            var groups = await query.AsNoTracking()
                .Cast<IStatisticalUnit>()
                .ToListAsync();
            return groups;
        }

        private IQueryable<EnterpriseGroup> GetQueryForEnterpriseGroups(IEnumerable<FieldEnum> fields)
        {
            var query = _context.EnterpriseGroups.AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.Region) || fieldLookup.Contains(FieldEnum.ActualAddress))
                query = query.Include(x => x.Address)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.ContactPerson))
                query = query.Include(x => x.PersonsUnits)
                    .ThenInclude(x => x.Person);

            return query;
        }

        private async Task<List<IStatisticalUnit>> ExecuteSampleFrameOnStatUnits(int? count,
            ExpressionGroup expressionGroup, IEnumerable<FieldEnum> fields)
        {
            var predicate = _statUnitExprParser.Parse(expressionGroup);
            var unitsQuery = GetQueryForUnits(fields);

            var query = unitsQuery
                .Where(predicate);
            if (count.HasValue)
                query = query.Take(count.Value);
            var units = await query.AsNoTracking()
                .Cast<IStatisticalUnit>()
                .ToListAsync();
            return units;
        }
    }
}
