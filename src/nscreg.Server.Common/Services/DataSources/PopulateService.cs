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

        public static int countGetBase = 0;
        public static int countHunit = 0;
        public static int countParse = 0;
        public static int countPostProcessor = 0;
        public static int countCheckRegion = 0;
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
        private readonly DataAccessService _dataAccessService;
        private readonly DataAccessPermissions _permissions;

        private bool UserIsAdmin { get; }

        public PopulateService((string source, string target)[] propMapping, DataSourceAllowedOperation operation, StatUnitTypes unitType, NSCRegDbContext context, string userId, DataAccessPermissions permissions)
        {
            _permissions = permissions;
            _dataAccessService = new DataAccessService(context);
            _permissionsHelper = new StatUnitCheckPermissionsHelper(context);
            _userId = userId;
            _statIdSourceKey = StatUnitKeyValueParser.GetStatIdMapping(propMapping) ?? throw new ArgumentNullException(nameof(propMapping), "StatId doesn't have source field(header)");
            _context = context;
            _unitType = unitType;
            _allowedOperation = operation;
            _postProcessor = new StatUnitPostProcessor(context);

            var userService = new UserService(context);
            UserIsAdmin = userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator).Result;
        }

        /// <summary>
        /// Method for populate unit
        /// </summary>
        /// <param name="raw">Parsed  data of a unit</param>
        /// <returns></returns>
        public async Task<(StatisticalUnit unit, bool isNew, string errors, StatisticalUnit historyUnit)> PopulateAsync(IReadOnlyDictionary<string, object> raw)
        {
            try
            {

                PopulateTracer.swGetBase.Start();
                if (_dataAccessService.CheckWritePermissions(_userId, _unitType))
                {
                    return (null, false, Resource.Error403, null);

                }
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

                if (!UserIsAdmin)
                    _permissionsHelper.CheckRegionOrActivityContains(_userId, resultUnit.Address?.RegionId, resultUnit.ActualAddress?.RegionId,
                        resultUnit.PostalAddress?.RegionId, resultUnit.Activities.Select(x => x.ActivityCategoryId).ToList());
                PopulateTracer.swCheckRegion.Stop();
                PopulateTracer.countCheckRegion++;

                resultUnit.UserId = _userId;

                Debug.WriteLine($@"GetBase {(double)PopulateTracer.swGetBase.ElapsedMilliseconds / PopulateTracer.countGetBase} ms
Hunit {(double)PopulateTracer.swHunit.ElapsedMilliseconds / PopulateTracer.countHunit} ms
Parse {(double)PopulateTracer.swParse.ElapsedMilliseconds / PopulateTracer.countParse} ms
Post {(double)PopulateTracer.swPostProcessor.ElapsedMilliseconds / PopulateTracer.countPostProcessor} ms
CheckRegion {(double)PopulateTracer.swCheckRegion.ElapsedMilliseconds / PopulateTracer.countCheckRegion} ms

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
