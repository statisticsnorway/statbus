using Microsoft.Extensions.Logging;
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
using nscreg.Server.Common.Services;
using nscreg.Data;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;
using nscreg.Resources.Languages;
using Microsoft.EntityFrameworkCore;

namespace nscreg.Server.DataUploadSvc
{
    internal class ImportExecutor
    {
        public static volatile int InterlockedInt = 0;
        public bool AnyWarnings { get; private set; }

        private readonly ILogger _logger;
        private readonly DbLogBuffer _logBuffer;
        private readonly bool _personsGoodQuality;
        private readonly int _elementsForRecreateContext;
        private AnalyzeService _analysisSvc;
        private readonly UserService _userService;
        private readonly CommonService _commonService;
        private readonly PopulateService _populateService;
        private readonly UpsertUnitBulkBuffer _upsertUnitBulkBuffer;
        private readonly SaveManager _saveManager;


#if DEBUG
        //public Stopwatch swPopulation = new Stopwatch();
        //public long populationCount = 0;

        //public Stopwatch swAnalyze = new Stopwatch();
        //public long analyzeCount = 0;

        //public Stopwatch swSave = new Stopwatch();
        //public long saveCount = 0;

        //public Stopwatch swDbLog = new Stopwatch();
        //public long dbLogCount = 0;
#endif
        public ImportExecutor(ILogger logger, DbLogBuffer logBuffer,
            bool personsGoodQuality, int elementsForRecreateContext, UserService userService,
            CommonService commonService, UpsertUnitBulkBuffer upsertUnitBulkBuffer,
            SaveManager saveManager, PopulateService populateService)
        {
            _personsGoodQuality = personsGoodQuality;
            _logger = logger;
            _logBuffer = logBuffer;
            _elementsForRecreateContext = elementsForRecreateContext;
            _userService = userService;
            _commonService = commonService;
            _populateService = populateService;
            _upsertUnitBulkBuffer = upsertUnitBulkBuffer;
            _saveManager = saveManager;
        }

        public Task Start(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues, int bufferMaxCount) => Task.Run(Job(dequeued, keyValues, bufferMaxCount));

        private Func<Task> Job(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues, int bufferMaxCount) => async () =>
        {
            var dbContextHelper = new DbContextHelper();
            var context = dbContextHelper.CreateDbContext(new string[] { });
            context.Database.SetCommandTimeout(180);
            await InitializeCacheForLookups(context);
            var permissions = await _commonService.InitializeDataAccessAttributes<IStatUnitM>(null, dequeued.UserId, dequeued.DataSource.StatUnitType);
            bool isAdmin = await _userService.IsInRoleAsync(dequeued.UserId, DefaultRoleNames.Administrator);
            int i = 0;
            foreach (var parsedUnit in keyValues)
            {
                //Interlocked.Increment(ref InterlockedInt);
                _logger.LogInformation("processing entity #{0}", i++);
                var startedAt = DateTime.Now;

                /// Populate Unit

                //swPopulation.Start();
                _logger.LogInformation("populating unit");
                var (populated, isNew, populateError, historyUnit) = await _populateService.PopulateAsync(parsedUnit, isAdmin, startedAt, _personsGoodQuality);
                //swPopulation.Stop();
                //populationCount += 1;
                if (populateError.HasValue())
                {
                    _logger.LogInformation("error during populating of unit: {0}", populateError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, populateError, analysisSummary: new List<string>() { populateError });
                    continue;
                }

                populated.DataSource = dequeued.DataSourceFileName;
                populated.ChangeReason = ChangeReasons.Edit;
                populated.EditComment = "Uploaded from data source file";

                /// Analyze Unit

                _logger.LogInformation(
                    "analyzing populated unit RegId={0}", populated.RegId > 0 ? populated.RegId.ToString() : "(new)");

                //swAnalyze.Start();

                var (analysisError, (errors, summary)) = await AnalyzeUnitAsync(populated, dequeued);
                //swAnalyze.Stop();
                //analyzeCount += 1;

                if (analysisError.HasValue())
                {
                    _logger.LogInformation("analysis attempt failed with error: {0}", analysisError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, analysisError);
                    continue;
                }
                if (errors.Any())
                {
                    _logger.LogInformation("analysis revealed {0} errors", errors.Count);
                    errors.Values.ForEach(x => x.ForEach(e => _logger.LogInformation(Resource.ResourceManager.GetString(e.ToString()))));
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Warning, string.Join(",", errors.SelectMany(c => c.Value)), errors, summary);
                    continue;
                }

                /// Save Unit

                _logger.LogInformation("saving unit");

                // swSave.Start();
                var (saveError, saved) = await _saveManager.SaveUnit(populated, dequeued.DataSource, dequeued.UserId, isNew, historyUnit);

                //swSave.Stop();
                // saveCount += 1;

                if (saveError.HasValue())
                {
                    _logger.LogError(saveError);
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
                    // swDbLog.Start();
                    var rawUnit = JsonConvert.SerializeObject(dequeued.DataSource.VariablesMappingArray.ToDictionary(x => x.target, x =>
                    {
                        var tmp = x.source.Split('.', 2);
                        return tmp[0];
                    }));
                    await _logBuffer.LogUnitUpload(
                            dequeued, rawUnit, startedAt, populated,
                            status, note ?? "", analysisErrors, analysisSummary);

                    //swDbLog.Stop();
                }
            }
            await _upsertUnitBulkBuffer.FlushAsync();
        };

        private async Task<(string, (IReadOnlyDictionary<string, string[]>, string[] test))> AnalyzeUnitAsync(IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if (queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
                return (null, (new Dictionary<string, string[]>(), new string[0]));

            AnalysisResult analysisResult;
            try
            {
                analysisResult = await _analysisSvc.AnalyzeStatUnit(unit, queueItem.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter, true, false);
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
