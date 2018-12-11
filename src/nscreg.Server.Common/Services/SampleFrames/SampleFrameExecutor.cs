using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
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

        public SampleFrameExecutor(NSCRegDbContext context, IConfiguration configuration)
        {
            _context = context;
            _statUnitExprParser = new ExpressionTreeParser<StatisticalUnit>(context, configuration);
            _enterpriseGroupExprParser = new ExpressionTreeParser<EnterpriseGroup>(context, configuration);
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
            var query = _context.StatisticalUnits.Where(x=>x.ParentId == null).AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.ActivityCodes) || fieldLookup.Contains(FieldEnum.MainActivity))
                query = query.Include(x => x.ActivitiesUnits)
                    .ThenInclude(x => x.Activity)
                    .ThenInclude(x => x.ActivityCategory);

            if (fieldLookup.Contains(FieldEnum.Region) || fieldLookup.Contains(FieldEnum.Address))
                query = query.Include(x => x.Address)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.ActualAddress))
                query = query.Include(x => x.ActualAddress)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.PostalAddress))
                query = query.Include(x => x.PostalAddress)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.InstSectorCodeId))
                query = query.Include(x => x.InstSectorCode);

            if (fieldLookup.Contains(FieldEnum.LegalFormId))
                query = query.Include(x => x.LegalForm);

            if (fieldLookup.Contains(FieldEnum.ContactPerson))
                query = query.Include(x => x.PersonsUnits)
                    .ThenInclude(x => x.Person);

            if (fieldLookup.Contains(FieldEnum.ForeignParticipationId))
                query = query.Include(x => x.ForeignParticipationCountriesUnits)
                    .ThenInclude(x=>x.Country);

            return query;
        }

        private bool CheckUnexistingFieldsInEnterpriseGroup(ExpressionGroup expressionGroup)
        {
            if (expressionGroup.Rules != null && expressionGroup.Rules.Any(x => x.Predicate.Field == FieldEnum.ForeignParticipationId || x.Predicate.Field == FieldEnum.FreeEconZone))
            {
                return true;
            }
            return expressionGroup.Groups != null && expressionGroup.Groups.Any(x => CheckUnexistingFieldsInEnterpriseGroup(x.Predicate));
        }

        private async Task<List<IStatisticalUnit>> ExecuteSampleFrameOnEnterpriseGroupsAsync(int? count, ExpressionGroup expressionGroup, IEnumerable<FieldEnum> fields)
        {
            if (CheckUnexistingFieldsInEnterpriseGroup(expressionGroup))
            {
                return new List<IStatisticalUnit>();
            }
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
            var query = _context.EnterpriseGroups.Where(x => x.ParentId == null).AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.Region) || fieldLookup.Contains(FieldEnum.Address))
                query = query.Include(x => x.Address)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.ActualAddress))
                query = query.Include(x => x.ActualAddress)
                    .ThenInclude(x => x.Region);

            if (fieldLookup.Contains(FieldEnum.PostalAddress))
                query = query.Include(x => x.PostalAddress)
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
