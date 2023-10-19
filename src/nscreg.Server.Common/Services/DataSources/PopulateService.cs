using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.DataSources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Server.Common.Services.DataSources
{

    /// <summary>
    /// Service for populating unit
    /// </summary>
    public class PopulateService
    {
        private readonly DataSourceAllowedOperation _allowedOperation;
        private readonly string _statIdSourceKey;
        private readonly StatUnitTypes _unitType;
        private readonly NSCRegDbContext _context;
        private readonly StatUnitPostProcessor _postProcessor;
        private readonly string _userId;
        private readonly StatUnitCheckPermissionsHelper _permissionsHelper;
        private readonly DataAccessPermissions _permissions;
        private readonly IMapper _mapper;

        public PopulateService((string source, string target)[] propMapping, DataSourceAllowedOperation operation,
            StatUnitTypes unitType, NSCRegDbContext context, string userId, DataAccessPermissions permissions,
            IMapper mapper)
        {
            _permissions = permissions;
            
            _permissionsHelper = new StatUnitCheckPermissionsHelper(context);
            _userId = userId;
            _statIdSourceKey = StatUnitKeyValueParser.GetStatIdMapping(propMapping) ?? throw new ArgumentNullException(nameof(propMapping), "StatId doesn't have source field(header)");
            _context = context;
            _unitType = unitType;
            _allowedOperation = operation;
            _postProcessor = new StatUnitPostProcessor(context);
            _mapper = mapper;
        }

        /// <summary>
        /// Method for populate unit
        /// </summary>
        /// <param name="raw">Parsed  data of a unit</param>
        /// <param name="isAdmin"></param>
        /// <param name="personsGoodQuality"></param>
        /// <returns></returns>
        public async Task<(StatisticalUnit unit, bool isNew, string errors, StatisticalUnit historyUnit)> PopulateAsync(IReadOnlyDictionary<string, object> raw, bool isAdmin, DateTime startDate, bool personsGoodQuality = true)
        {
            try
            {
                var (resultUnit, isNew) = await GetStatUnitBase(raw);

                if (_allowedOperation == DataSourceAllowedOperation.Create && !isNew)
                {
                    var statId = raw.GetValueOrDefault(_statIdSourceKey);
                    return (resultUnit, false, string.Format(Resource.StatisticalUnitWithSuchStatIDAlreadyExists, statId), null);
                }

                if (_allowedOperation == DataSourceAllowedOperation.Alter && isNew)
                {
                    return (resultUnit, true,
                        $"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({resultUnit.StatId})", null);
                }
                StatisticalUnit historyUnit = null;

                if (_allowedOperation == DataSourceAllowedOperation.Alter ||
                                        _allowedOperation == DataSourceAllowedOperation.CreateAndAlter && !isNew)
                {
                    historyUnit = GetStatUnitSetHelper.CreateByType(_unitType);
                    _mapper.Map(resultUnit, historyUnit);
                }
                StatUnitKeyValueParser.ParseAndMutateStatUnit(raw, resultUnit, _context, _userId, _permissions, personsGoodQuality);
                var errors = await _postProcessor.PostProcessStatUnitsUpload(resultUnit);

                if (!isAdmin)
                {
                    var listRegionsIds = new List<int?> { resultUnit.ActualAddress?.RegionId, resultUnit.PostalAddress?.RegionId }.Where(x => x != null).Select(x => (int)x).ToList();
                    _permissionsHelper.CheckRegionOrActivityContains(_userId, listRegionsIds, resultUnit.Activities.Select(x => x.ActivityCategoryId).ToList(), isUploadService:true);
                }

                resultUnit.UserId = _userId;
                resultUnit.StartPeriod = startDate;
                resultUnit.RegIdDate = startDate;
                return (resultUnit, isNew, errors, historyUnit);
            }
            catch (Exception ex)
            {
                return (ex.Data["unit"] as StatisticalUnit, false, ex.Message, null);
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
