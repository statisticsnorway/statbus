using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Server.Common.Services.SampleFrames
{
    public class SampleFrameExecutor
    {
        private readonly NSCRegDbContext _context;
        private readonly ExpressionTreeParser<EnterpriseGroup> _enterpriseGroupExprParser;
        private readonly ExpressionTreeParser<StatisticalUnit> _statUnitExprParser;
        private readonly PropertyValuesProvider _propertyValuesProvider;
        private readonly CsvHelper _csvHelper;

        public SampleFrameExecutor(NSCRegDbContext context, IConfiguration configuration)
        {
            _context = context;
            _statUnitExprParser = new ExpressionTreeParser<StatisticalUnit>(context, configuration);
            _enterpriseGroupExprParser = new ExpressionTreeParser<EnterpriseGroup>(context, configuration);
            _propertyValuesProvider = new PropertyValuesProvider(context);
            _csvHelper = new CsvHelper();
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Execute(ExpressionGroup tree,
            List<FieldEnum> fields, int? count = null)
        {
            var (unitsQuery, unitsEntQuery) = GetRows(tree, fields);
            var units = new List<IStatisticalUnit>();
            var unitsEnt = new List<IStatisticalUnit>();

            if (count.HasValue)
            {
                units = await unitsQuery.Take(count.Value).Cast<IStatisticalUnit>().ToListAsync();
                var rest = (int)count - units.Count;
                if (rest > 0)
                {
                    unitsEnt = await unitsEntQuery.Take(rest).Cast<IStatisticalUnit>().ToListAsync();
                }
            }

            return units.Concat(unitsEnt).Select(unit =>
                fields.ToDictionary(field => field, field => _propertyValuesProvider.GetValue(unit, field)));
        }

        public async Task ExecuteToFile(ExpressionGroup tree, List<FieldEnum> fields, string filePath)
        {
            var (unitsQuery, unitsEntQuery) = GetRows(tree, fields);
            
            using (StreamWriter writer = File.AppendText(filePath))
            {
                await BatchWrite(writer, unitsQuery, fields, true, 50000);
                await BatchWrite(writer, unitsEntQuery, fields, false, 50000);
            }
        }

        private async Task BatchWrite(StreamWriter writer, IQueryable<IStatisticalUnit> query, List<FieldEnum> fields, bool withHeaders = false, int batchSize = 10000)
        {
            int currentPage = 0;
            int bufferCount = 0;
            do
            {
                currentPage++;
                var buffer = await query.Skip((currentPage - 1) * batchSize).Take(batchSize).ToListAsync();
                var csvString = _csvHelper.ConvertToCsv(buffer.Select(unit =>
                    fields.ToDictionary(field => field, field => _propertyValuesProvider.GetValue(unit, field))), withHeaders && currentPage == 1);
                string lvBOM = Encoding.UTF8.GetString(Encoding.UTF8.GetPreamble());
                writer.Write(currentPage == 1 ? lvBOM + csvString : csvString);
                bufferCount = buffer.Count;
            } while (bufferCount == batchSize);
        }

        private (IQueryable<StatisticalUnit>, IQueryable<EnterpriseGroup>) GetRows(ExpressionGroup tree, List<FieldEnum> fields)
        {
            var predicate = _statUnitExprParser.Parse(tree);
            var query = GetQueryForUnits(fields).Where(predicate);

            var queryEnt = Enumerable.Empty<EnterpriseGroup>().AsQueryable();
            if (!CheckUnexistingFieldsInEnterpriseGroup(tree))
            {
                var predicateEnt = _enterpriseGroupExprParser.Parse(tree);
                queryEnt = GetQueryForEnterpriseGroups(fields).Where(predicateEnt);
            }

            return (query.AsNoTracking(), queryEnt.AsNoTracking());
        }

        private IQueryable<StatisticalUnit> GetQueryForUnits(IEnumerable<FieldEnum> fields)
        {
            var query = _context.StatisticalUnits.AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.ActivityCodes) || fieldLookup.Contains(FieldEnum.MainActivity))
                query = query.Include(x => x.ActivitiesUnits)
                    .ThenInclude(x => x.Activity)
                    .ThenInclude(x => x.ActivityCategory);

            if (fieldLookup.Contains(FieldEnum.Region))
                query = query.Include(x => x.ActualAddress)
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

            return query.Where(c => !c.IsDeleted);
        }

        private bool CheckUnexistingFieldsInEnterpriseGroup(ExpressionGroup expressionGroup)
        {
            if (expressionGroup.Rules != null && expressionGroup.Rules.Any(x => x.Predicate.Field == FieldEnum.ForeignParticipationId || x.Predicate.Field == FieldEnum.FreeEconZone))
            {
                return true;
            }
            return expressionGroup.Groups != null && expressionGroup.Groups.Any(x => CheckUnexistingFieldsInEnterpriseGroup(x.Predicate));
        }

        private IQueryable<EnterpriseGroup> GetQueryForEnterpriseGroups(IEnumerable<FieldEnum> fields)
        {
            var query = _context.EnterpriseGroups.AsQueryable();
            var fieldLookup = fields.ToLookup(x => x);

            if (fieldLookup.Contains(FieldEnum.Region))
                query = query.Include(x => x.ActualAddress)
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

            return query.Where(c => !c.IsDeleted);
        }
    }
}
