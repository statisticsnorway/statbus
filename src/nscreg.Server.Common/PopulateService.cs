using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.DataSources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common
{ 
    public class PopulateService
    {
        private readonly Dictionary<string, string[]> _mappings;
        private readonly DataSourceAllowedOperation _allowedOperation;
        private readonly DataSourceUploadTypes _uploadType;
        private readonly string _statIdSourceKey;
        private readonly StatUnitTypes _unitType;
        private readonly NSCRegDbContext _context;
        public PopulateService((string source, string target)[] propMapping, DataSourceAllowedOperation operation, DataSourceUploadTypes uploadType, StatUnitTypes unitType, NSCRegDbContext context)
        {
            _statIdSourceKey = StatUnitKeyValueParser.GetStatIdSourceKey(propMapping) ?? throw new ArgumentNullException(nameof(propMapping), "StatId doesn't have source field(header)");
            _context = context;
            _unitType = unitType;
            _allowedOperation = operation;
            _uploadType = uploadType;
            _mappings = propMapping
                .GroupBy(x => x.source)
                .ToDictionary(x => x.Key, x => x.Select(y => y.target).ToArray());
        }

        public async Task<(StatisticalUnit, string)> PopulateAsync(IReadOnlyDictionary<string, object> raw)
        {
            var resultUnit = await GetStatUnitBase(_allowedOperation, raw);

            raw = await TransformReferenceField(raw, _mappings, "Persons.Person.Role", (value) =>
            {
                return _context.PersonTypes.FirstOrDefaultAsync(x =>
                    x.Name == value || x.NameLanguage1 == value || x.NameLanguage2 == value);
            });

            ParseAndMutateStatUnit(_mappings, raw, resultUnit);

            var errors = await _postProcessor.FillIncompleteDataOfStatUnit(resultUnit, _uploadType);

            return (resultUnit, errors);

            
        }

        private async Task<StatisticalUnit> GetStatUnitBase(DataSourceAllowedOperation operation, IReadOnlyDictionary<string, object> raw)
        {
            StatisticalUnit existing = null;
            if (_statIdSourceKey.HasValue() &&
            operation != DataSourceAllowedOperation.Create && raw.TryGetValue(_statIdSourceKey, out var statId))
            {
                existing = await _getStatUnitSet[_unitType]
                    .FirstOrDefaultAsync(x => x.StatId == statId.ToString());
            }

            else if (_uploadType == DataSourceUploadTypes.Activities)
                throw new InvalidOperationException("Missing statId required for activity upload");


            if (existing == null) return CreateByType[_unitType]();

            _context.Entry(existing).State = EntityState.Detached;
            return existing;
        }


    }
}
