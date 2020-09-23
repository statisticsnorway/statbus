using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.DataSources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    /// <summary>
    /// Service for populating unit
    /// </summary>
    public class PopulateService
    {
        private readonly DataSourceAllowedOperation _allowedOperation;
        private readonly string _personRoleSource;
        private readonly DataSourceUploadTypes _uploadType;
        private readonly string _statIdSourceKey;
        private readonly StatUnitTypes _unitType;
        private readonly NSCRegDbContext _context;
        private readonly StatUnitPostProcessor _postProcessor;
        public PopulateService((string source, string target)[] propMapping, DataSourceAllowedOperation operation, DataSourceUploadTypes uploadType, StatUnitTypes unitType, NSCRegDbContext context)
        {
            _personRoleSource = propMapping.FirstOrDefault(c => c.target == "Persons.Person.Role").target;
            _statIdSourceKey = StatUnitKeyValueParser.GetStatIdMapping(propMapping) ?? throw new ArgumentNullException(nameof(propMapping), "StatId doesn't have source field(header)");
            _context = context;
            _unitType = unitType;
            _allowedOperation = operation;
            _uploadType = uploadType;
            _postProcessor = new StatUnitPostProcessor(context);
        }

        /// <summary>
        /// Eagerly loads lookups to lower number of requests to DB
        /// </summary>
        /// <returns></returns>
        public async Task InitializeCacheForLookups()
        {
            await _context.ActivityCategories.LoadAsync();
            await _context.PersonTypes.LoadAsync();
            await _context.RegistrationReasons.LoadAsync();
            await _context.Regions.LoadAsync();
            await _context.UnitsSize.LoadAsync();
            await _context.Statuses.LoadAsync();
            await _context.ReorgTypes.LoadAsync();
            await _context.SectorCodes.LoadAsync();
            await _context.DataSourceClassifications.LoadAsync();
            await _context.LegalForms.LoadAsync();
            await _context.ForeignParticipations.LoadAsync();
            await _context.Countries.LoadAsync();
        }

        /// <summary>
        /// Method for populate unit
        /// </summary>
        /// <param name="raw">Parsed  data of a unit</param>
        /// <returns></returns>
        public async Task<(StatisticalUnit unit, bool isNew, string errors)> PopulateAsync(IReadOnlyDictionary<string, object> raw)
        {
            try
            {
                var (resultUnit, isNew) = await GetStatUnitBase(raw);

                // Check for operation errors

                if (_allowedOperation == DataSourceAllowedOperation.Create && !isNew)
                {
                    var statId = raw.GetValueOrDefault(_statIdSourceKey);
                    return (resultUnit, false, string.Format(Resource.StatisticalUnitWithSuchStatIDAlreadyExists, statId));
                }

                if (_allowedOperation == DataSourceAllowedOperation.Alter && isNew)
                {
                    return (resultUnit, true,
                        $"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({resultUnit.StatId})");
                }

                StatUnitKeyValueParser.ParseAndMutateStatUnit(raw, resultUnit, _context);

                var errors = await _postProcessor.PostProcessStatUnitsUpload(resultUnit);

                return (resultUnit, isNew, errors);
            }
            catch (Exception ex)
            {
                return (ex.Data["unit"] as StatisticalUnit, false, ex.Message);
            }
        }

        /// <summary>
        /// Returns existed or new stat unit
        /// </summary>
        /// <param name="raw">Parsed data of a unit</param>
        /// <returns></returns>
        private async Task<(StatisticalUnit unit, bool isNew)> GetStatUnitBase(IReadOnlyDictionary<string, object> raw)
        {
            if (!_statIdSourceKey.HasValue() || !raw.TryGetValue(_statIdSourceKey, out var statId))
                return (GetStatUnitSetHelper.CreateByType(_unitType), true);

            var existing = await GetStatUnitSetHelper
                .GetStatUnitSet(_context, _unitType)
                .FirstOrDefaultAsync(x => x.StatId == statId.ToString());

            if (existing == null)
            {
                var createdUnit = GetStatUnitSetHelper.CreateByType(_unitType);
                createdUnit.StatId = statId.ToString();
                return (createdUnit, true);
            }

            return (unit: existing, isNew: false);
        }
    }
}
