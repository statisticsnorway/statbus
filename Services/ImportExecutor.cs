using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using LogStatus = nscreg.Data.Constants.DataUploadingLogStatuses;
using nscreg.Server.Common.Services.DataSources;
using Newtonsoft.Json;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums;
using nscreg.Business.Analysis.StatUnit;
using System.Linq;
using nscreg.Data;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Extensions;
using nscreg.Resources.Languages;
using Microsoft.EntityFrameworkCore;
using NLog;
using AutoMapper;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Services
{
    public class ImportExecutor
    {
        public bool AnyWarnings { get; private set; }
        private static readonly Logger _logger = LogManager.GetCurrentClassLogger();
        private readonly DbLogBuffer _logBuffer;
        private readonly IMapper _mapper;
        private readonly IUserService _userService;
        private readonly ServicesSettings _servicesSettings;
        private readonly IStatUnitAnalyzeService _analyzeService;
        private readonly CommonService _commonService;

        public ImportExecutor(DbLogBuffer logBuffer,
            IUserService userService, IMapper mapper, CommonService commonService, ServicesSettings servicesSettings, IStatUnitAnalyzeService analyzeService)
        {
            _logBuffer = logBuffer;
            _userService = userService;
            _mapper = mapper;
            _commonService = commonService;
            _servicesSettings = servicesSettings;
            _analyzeService = analyzeService;
        }

        public Task Start(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues) => Task.Run(Job(dequeued, keyValues));

        private Func<Task> Job(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues) => async () =>
        {
            var dbContextHelper = new DbContextHelper();
            var context = dbContextHelper.CreateDbContext(new string[] { });
            context.Database.SetCommandTimeout(180);
            await InitializeCacheForLookups(context);
            var permissions = await _commonService.InitializeDataAccessAttributes<IStatUnitM>(null, dequeued.UserId, dequeued.DataSource.StatUnitType);
            var sqlBulkBuffer = new UpsertUnitBulkBuffer(context, new ElasticService(context, _mapper), permissions, dequeued, _mapper, _commonService, _servicesSettings.DataUploadMaxBufferCount);
            var populateService = new PopulateService(dequeued.DataSource.VariablesMappingArray, dequeued.DataSource.AllowedOperations, dequeued.DataSource.StatUnitType, context, dequeued.UserId, permissions, _mapper);
            var saveService = new SaveManager(new BulkUpsertUnitService(context, sqlBulkBuffer, _commonService, permissions, _mapper, dequeued.UserId));
            bool isAdmin = await _userService.IsInRoleAsync(dequeued.UserId, DefaultRoleNames.Administrator);
            int i = 0;
            foreach (var parsedUnit in keyValues)
            {
                _logger.Info("processing entity #{0}", i++);
                var startedAt = DateTime.Now;

                /// Populate Unit
                _logger.Info("populating unit");
                (StatisticalUnit populated, bool isNew, string populateError, StatisticalUnit historyUnit) = await populateService.PopulateAsync(parsedUnit, isAdmin, startedAt, _servicesSettings.PersonGoodQuality);

                if (populateError.HasValue())
                {
                    _logger.Info("error during populating of unit: {0}", populateError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, populateError, analysisSummary: new List<string>() { populateError });
                    continue;
                }

                populated.DataSource = dequeued.DataSourceFileName;
                populated.ChangeReason = ChangeReasons.Edit;
                populated.EditComment = "Uploaded from data source file";

                /// Analyze Unit

                _logger.Info(
                    "analyzing populated unit RegId={0}", populated.RegId > 0 ? populated.RegId.ToString() : "(new)");

                var (analysisError, (errors, summary)) = await AnalyzeUnitAsync(populated, dequeued);

                if (analysisError.HasValue())
                {
                    _logger.Info("analysis attempt failed with error: {0}", analysisError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, analysisError);
                    continue;
                }
                if (errors.Any())
                {
                    _logger.Info("analysis revealed {0} errors", errors.Count);
                    errors.Values.ForEach(x => x.ForEach(e => _logger.Info(Resource.ResourceManager.GetString(e.ToString()))));
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Warning, string.Join(",", errors.SelectMany(c => c.Value)), errors, summary);
                    continue;
                }

                /// Save Unit

                _logger.Info("saving unit");

                var (saveError, saved) = await saveService.SaveUnit(populated, dequeued.DataSource, dequeued.UserId, isNew, historyUnit);

                if (saveError.HasValue())
                {
                    _logger.Error(saveError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Warning, saveError);
                    continue;
                }

                if (!saved) AnyWarnings = true;
                await LogUpload(saved ? LogStatus.Done : LogStatus.Warning);


                async Task LogUpload(LogStatus status, string note = "",
                        IReadOnlyDictionary<string, string[]> analysisErrors = null,
                        IEnumerable<string> analysisSummary = null)
                {

                    var rawUnit = JsonConvert.SerializeObject(dequeued.DataSource.VariablesMappingArray.ToDictionary(x => x.target, x =>
                    {
                        var tmp = x.source.Split('.', 2);
                        return tmp[0];
                    }));
                    await _logBuffer.LogUnitUpload(
                            dequeued, rawUnit, startedAt, populated,
                            status, note ?? "", analysisErrors, analysisSummary);

                }
            }
            await sqlBulkBuffer.FlushAsync();
        };

        private async Task<(string, (IReadOnlyDictionary<string, string[]>, string[] test))> AnalyzeUnitAsync(IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if (queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
                return (null, (new Dictionary<string, string[]>(), new string[0]));

            AnalysisResult analysisResult;
            try
            {
                analysisResult = await _analyzeService.AnalyzeStatUnit(unit, queueItem.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter, true, false);
            }
            catch (Exception ex)
            {
                return (ex.Message, (null, null));
            }
            return (null, (
                analysisResult.Messages,
                analysisResult.SummaryMessages?.ToArray() ?? Array.Empty<string>()));
        }

        private static async Task InitializeCacheForLookups(NSCRegDbContext context)
        {
            await context.ActivityCategories.LoadAsync();
            await context.PersonTypes.LoadAsync();
            await context.RegistrationReasons.LoadAsync();
            await context.Regions.LoadAsync();
            await context.UnitsSize.LoadAsync();
            await context.Statuses.LoadAsync();
            await context.ReorgTypes.LoadAsync();
            await context.SectorCodes.LoadAsync();
            await context.DataSourceClassifications.LoadAsync();
            await context.LegalForms.LoadAsync();
            await context.ForeignParticipations.LoadAsync();
            await context.Countries.LoadAsync();
            await context.UserRegions.LoadAsync();
        }
    }
}
