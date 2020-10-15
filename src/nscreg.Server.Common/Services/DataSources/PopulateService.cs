using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.DataSources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Server.Common.Services.DataSources
{
    class PopulateTracer
    {
        public static Stopwatch swGetBase = new Stopwatch();
        public static Stopwatch swHunit = new Stopwatch();
        public static Stopwatch swParse = new Stopwatch();
        public static Stopwatch swPostProcessor = new Stopwatch();
        public static Stopwatch swCheckRegion = new Stopwatch();
        public static Stopwatch swFirstOrDefaultFromDB = new Stopwatch();
        public static Stopwatch swCreateByType = new Stopwatch();
        public static Stopwatch swSourceKeyCheck = new Stopwatch();

        public static int countGetBase = 0;
        public static int countHunit = 0;
        public static int countParse = 0;
        public static int countPostProcessor = 0;
        public static int countCheckRegion = 0;
        public static int countFirstOrDefaultFromDB = 0;
        public static int countCreateByType = 0;
        public static int countSourceKeyCheck = 0;
    }

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

        public PopulateService((string source, string target)[] propMapping, DataSourceAllowedOperation operation, StatUnitTypes unitType, NSCRegDbContext context, string userId, DataAccessPermissions permissions)
        {
            _permissions = permissions;
            
            _permissionsHelper = new StatUnitCheckPermissionsHelper(context);
            _userId = userId;
            _statIdSourceKey = StatUnitKeyValueParser.GetStatIdMapping(propMapping) ?? throw new ArgumentNullException(nameof(propMapping), "StatId doesn't have source field(header)");
            _context = context;
            _unitType = unitType;
            _allowedOperation = operation;
            _postProcessor = new StatUnitPostProcessor(context);
        }

        /// <summary>
        /// Method for populate unit
        /// </summary>
        /// <param name="raw">Parsed  data of a unit</param>
        /// <param name="isAdmin"></param>
        /// <returns></returns>
        public async Task<(StatisticalUnit unit, bool isNew, string errors, StatisticalUnit historyUnit)> PopulateAsync(IReadOnlyDictionary<string, object> raw, bool isAdmin)
        {
            try
            {

                PopulateTracer.swGetBase.Start();
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
                PopulateTracer.swGetBase.Stop();
                PopulateTracer.countGetBase++;

                PopulateTracer.swHunit.Start();
                StatisticalUnit historyUnit = null;

                if (_allowedOperation == DataSourceAllowedOperation.Alter ||
                                        _allowedOperation == DataSourceAllowedOperation.CreateAndAlter && !isNew)
                {
                    historyUnit = GetStatUnitSetHelper.CreateByType(_unitType);
                    Mapper.Map(resultUnit, historyUnit);
                }
                PopulateTracer.swHunit.Stop();
                PopulateTracer.countHunit++;

                PopulateTracer.swParse.Start();
                StatUnitKeyValueParser.ParseAndMutateStatUnit(raw, resultUnit, _context, _userId, _permissions);
                PopulateTracer.swParse.Stop();
                PopulateTracer.countParse++;

                PopulateTracer.swPostProcessor.Start();
                var errors = await _postProcessor.PostProcessStatUnitsUpload(resultUnit);
                PopulateTracer.swPostProcessor.Stop();
                PopulateTracer.countPostProcessor++;

                PopulateTracer.swCheckRegion.Start();

                if (!isAdmin)
                {
                    var listRegionsIds = new List<int?> { resultUnit.Address?.RegionId, resultUnit.ActualAddress?.RegionId, resultUnit.PostalAddress?.RegionId }.Where(x => x != null).Select(x => (int)x).ToList();
                    _permissionsHelper.CheckRegionOrActivityContains(_userId, listRegionsIds, resultUnit.Activities.Select(x => x.ActivityCategoryId).ToList());
                }
                PopulateTracer.swCheckRegion.Stop();
                PopulateTracer.countCheckRegion++;

                resultUnit.UserId = _userId;

                Debug.WriteLine($@"GetBase {(double)PopulateTracer.swGetBase.ElapsedMilliseconds / PopulateTracer.countGetBase : 0.00} ms
  FirstOrDefault {(double)PopulateTracer.swFirstOrDefaultFromDB.ElapsedMilliseconds / PopulateTracer.countFirstOrDefaultFromDB : 0.00} ms
  CreateByType {(double)PopulateTracer.swCreateByType.ElapsedMilliseconds / PopulateTracer.countCreateByType : 0.00} ms
  SourceKeyCheck {(double)PopulateTracer.swSourceKeyCheck.ElapsedMilliseconds / PopulateTracer.countSourceKeyCheck : 0.00} ms
Hunit {(double)PopulateTracer.swHunit.ElapsedMilliseconds / PopulateTracer.countHunit : 0.00} ms
Parse {(double)PopulateTracer.swParse.ElapsedMilliseconds / PopulateTracer.countParse : 0.00} ms
Post {(double)PopulateTracer.swPostProcessor.ElapsedMilliseconds / PopulateTracer.countPostProcessor : 0.00} ms
CheckRegion {(double)PopulateTracer.swCheckRegion.ElapsedMilliseconds / PopulateTracer.countCheckRegion : 0.00} ms

");

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
            PopulateTracer.swSourceKeyCheck.Start();
            if (!_statIdSourceKey.HasValue() || !raw.TryGetValue(_statIdSourceKey, out var statId))
                return (GetStatUnitSetHelper.CreateByType(_unitType), true);
            PopulateTracer.swSourceKeyCheck.Stop();
            PopulateTracer.countSourceKeyCheck++;


            PopulateTracer.swFirstOrDefaultFromDB.Start();
            var existing = await GetStatUnitSetHelper
                .GetStatUnitSet(_context, _unitType)
                .FirstOrDefaultAsync(x => x.StatId == statId.ToString());
            PopulateTracer.swFirstOrDefaultFromDB.Stop();
            PopulateTracer.countFirstOrDefaultFromDB++;

            
            if (existing == null)
            {
                PopulateTracer.swCreateByType.Start();
                var createdUnit = GetStatUnitSetHelper.CreateByType(_unitType);
                createdUnit.StatId = statId.ToString();
                PopulateTracer.swCreateByType.Stop();
                PopulateTracer.countCreateByType++;
                return (createdUnit, true);
            }


            return (unit: existing, isNew: false);
        }
    }
}
