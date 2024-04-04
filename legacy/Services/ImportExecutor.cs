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
using Microsoft.Extensions.Configuration;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Configuration.DBMandatoryFields;

namespace nscreg.Services
{
    public class ImportExecutor
    {
        public bool AnyWarnings { get; private set; }
        private static readonly Logger _logger = LogManager.GetCurrentClassLogger();
        private readonly IMapper _mapper;
        private readonly ServicesSettings _servicesSettings;
        private readonly IConfiguration _configuration;

        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly ValidationSettings _validationSettings;

        public ImportExecutor(IMapper mapper, ServicesSettings servicesSettings, IConfiguration configuration)
        {
            _mapper = mapper;
            _servicesSettings = servicesSettings;
            _configuration = configuration;
            _analysisRules = configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            _mandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();
            _validationSettings = configuration.GetSection(nameof(ValidationSettings)).Get<ValidationSettings>();
        }

        public Task Start(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues) => Task.Run(Job(dequeued, keyValues));

        private Func<Task> Job(DataSourceQueue dequeued, IReadOnlyDictionary<string, object>[] keyValues) => async () =>
        {
            var dbContextHelper = new DbContextHelper(_configuration);
            NSCRegDbContext context = null;
            UpsertUnitBulkBuffer sqlBulkBuffer = null;
            PopulateService populateService = null;
            SaveManager saveService = null;
            IStatUnitAnalyzeService analyzeService = null;
            DbLogBuffer logBuffer = null;
            bool isAdmin = false;
            for (int i = 0; i < keyValues.Length; i++)
            {
                var parsedUnit = keyValues[i];
                if(i % _servicesSettings.DataUploadMaxBufferCount == 0)
                {
                    if(sqlBulkBuffer != null)
                    {
                        _logger.Debug("Flushing");
                        await sqlBulkBuffer.FlushAsync();
                        await logBuffer.FlushAsync();
                        await context.DisposeAsync();
                    }

                    context = dbContextHelper.CreateDbContext(new string[] { });
                    context.Database.SetCommandTimeout(180);
                    await InitializeCacheForLookups(context);
                    var userService = new UserService(context, _mapper);
                    analyzeService = new AnalyzeService(context, _analysisRules, _mandatoryFields, _validationSettings);
                    logBuffer = new DbLogBuffer(context, _servicesSettings.DataUploadMaxBufferCount);
                    var permissions = await new CommonService(context, _mapper).InitializeDataAccessAttributes<IStatUnitM>(userService, null, dequeued.UserId, dequeued.DataSource.StatUnitType);
                    sqlBulkBuffer = new UpsertUnitBulkBuffer(context, new ElasticService(context, _mapper), permissions, dequeued, _mapper, _servicesSettings.DataUploadMaxBufferCount);
                    populateService = new PopulateService(dequeued.DataSource.VariablesMappingArray, dequeued.DataSource.AllowedOperations, dequeued.DataSource.StatUnitType, context, dequeued.UserId, permissions, _mapper);
                    saveService = new SaveManager(context, sqlBulkBuffer, permissions, _mapper, dequeued.UserId);
                    isAdmin = await userService.IsInRoleAsync(dequeued.UserId, DefaultRoleNames.Administrator);
                }

                _logger.Debug("processing entity #{0}", i);
                var startedAt = DateTime.Now;

                /// Populate Unit
                _logger.Trace("populating unit");
                (StatisticalUnit populated, bool isNew, string populateError, StatisticalUnit historyUnit) = await populateService.PopulateAsync(parsedUnit, isAdmin, startedAt, _servicesSettings.PersonGoodQuality);

                if (populateError.HasValue())
                {
                    _logger.Trace("error during populating of unit: {0}", populateError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, populateError, analysisSummary: new List<string>() { populateError });
                    continue;
                }

                populated.DataSource = dequeued.DataSourceFileName;
                populated.ChangeReason = ChangeReasons.Edit;
                populated.EditComment = "Uploaded from data source file";

                /// Analyze Unit

                _logger.Trace("analyzing populated unit RegId={0}", populated.RegId > 0 ? populated.RegId.ToString() : "(new)");

                var (analysisError, (errors, summary)) = await AnalyzeUnitAsync(analyzeService, populated, dequeued);

                if (analysisError.HasValue())
                {
                    _logger.Trace("analysis attempt failed with error: {0}", analysisError);
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Error, analysisError);
                    continue;
                }
                if (errors.Any())
                {
                    _logger.Trace("analysis revealed {0} errors", errors.Count);
                    errors.Values.ForEach(x => x.ForEach(e => _logger.Trace(Resource.ResourceManager.GetString(e.ToString()))));
                    AnyWarnings = true;
                    await LogUpload(LogStatus.Warning, string.Join(",", errors.SelectMany(c => c.Value)), errors, summary);
                    continue;
                }

                /// Save Unit

                _logger.Trace("saving unit");

                var (saveError, saved) = await saveService.SaveUnit(populated, dequeued.DataSource, dequeued.UserId, isNew, historyUnit);

                if (saveError.HasValue())
                {
                    _logger.Debug(saveError);
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
                    await logBuffer.LogUnitUpload(
                            dequeued, rawUnit, startedAt, populated,
                            status, note ?? "", analysisErrors, analysisSummary);

                }
            }
            await sqlBulkBuffer.FlushAsync();
        };

        private async Task<(string, (IReadOnlyDictionary<string, string[]>, string[] test))> AnalyzeUnitAsync(IStatUnitAnalyzeService analyzeService, IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if (queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
                return (null, (new Dictionary<string, string[]>(), new string[0]));

            AnalysisResult analysisResult;
            try
            {
                analysisResult = await analyzeService.AnalyzeStatUnit(unit, queueItem.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter, true, false);
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
            await context.ActivityCategories.AsNoTracking().LoadAsync();
            await context.PersonTypes.AsNoTracking().LoadAsync();
            await context.RegistrationReasons.AsNoTracking().LoadAsync();
            await context.Regions.AsNoTracking().LoadAsync();
            await context.UnitSizes.AsNoTracking().LoadAsync();
            await context.UnitStatuses.AsNoTracking().LoadAsync();
            await context.ReorgTypes.AsNoTracking().LoadAsync();
            await context.SectorCodes.AsNoTracking().LoadAsync();
            await context.DataSourceClassifications.AsNoTracking().LoadAsync();
            await context.LegalForms.AsNoTracking().LoadAsync();
            await context.ForeignParticipations.AsNoTracking().LoadAsync();
            await context.Countries.AsNoTracking().LoadAsync();
            await context.UserRegions.AsNoTracking().LoadAsync();
        }
    }
}
