using Microsoft.EntityFrameworkCore.Internal;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;
using System.Collections.Concurrent;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.DataUploadSvc
{
    /// <summary>
    /// Queue class
    /// </summary>
    internal class QueueJob : IJob
    {
        private readonly ILogger _logger;
        public int Interval { get; }
        private QueueService _queueSvc;
        private DbLogBuffer _logBuffer;
        private AnalyzeService _analysisSvc;
        private readonly int _dbLogBufferMaxCount;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private NSCRegDbContext _context;
        private ElasticBulkService _elasticBulkService;
       
        public QueueJob(
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields,
            ValidationSettings validationSettings, int bufferLogMaxCount)
        {
            _logger = logger;
            Interval = dequeueInterval;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _dbMandatoryFields = dbMandatoryFields;
            _validationSettings = validationSettings;
            _dbLogBufferMaxCount = bufferLogMaxCount;
            //AddScopedServices();
        }

        private void AddScopedServices()
        {
            var dbContextHelper = new DbContextHelper();
            _context = dbContextHelper.CreateDbContext(new string[] { });
            _queueSvc = new QueueService(_context);
            _elasticBulkService = new ElasticBulkService();
            _analysisSvc = new AnalyzeService(_context, _statUnitAnalysisRules, _dbMandatoryFields, _validationSettings);
            _logBuffer = new DbLogBuffer(_context, _dbLogBufferMaxCount);
        }

        /// <summary>
        /// Eagerly loads lookups to lower number of requests to DB
        /// </summary>
        /// <returns></returns>
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
        }

        /// <summary>
        /// Queue execution method
        /// </summary>
        public async Task Execute(CancellationToken cancellationToken)
        {
            AddScopedServices();
            _logger.LogInformation("dequeue attempt...");
            var (dequeueError, dequeued) = await Dequeue();
            if (dequeueError.HasValue())
            {
                _logger.LogInformation("dequeue failed with error: {0}", dequeueError);
                return;
            }
            if (dequeued == null) return;

            _logger.LogInformation("mutation queue file #{0}", dequeued.Id);

            var mutateError = await MutateFileAsync(dequeued);
            if (mutateError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", mutateError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, mutateError);
            }

            Stopwatch swCycle = new Stopwatch();
            swCycle.Start();

            var tasks = new BlockingCollection<IReadOnlyDictionary<string, object>>(new ConcurrentQueue<IReadOnlyDictionary<string, object>>());

            var executors = new List<ImportExecutor>() {
                new ImportExecutor(_statUnitAnalysisRules,_dbMandatoryFields,_validationSettings, _logger, _logBuffer,_elasticBulkService),
                new ImportExecutor(_statUnitAnalysisRules,_dbMandatoryFields,_validationSettings, _logger, _logBuffer,_elasticBulkService),
            };

            var parseTask = Task.Run(() => ParseFile(dequeued, tasks), cancellationToken);

            executors.ForEach(x => x.UseTasksQueue(tasks));
            var anyWarnings = false;
            var tasksArray = executors.Select(x => x.Start(dequeued)).Append(parseTask).ToArray();

            await CatchAndLogException(async () => await Task.WhenAll(tasksArray), () => anyWarnings = true);
            await CatchAndLogException(async () => await _logBuffer.FlushAsync(), () => anyWarnings = true);
            await CatchAndLogException(async () => await _elasticBulkService.FlushBulkBuffer(), () => anyWarnings = true);
            _logger.LogWarning($"End Total {swCycle.Elapsed};");

            await _queueSvc.FinishQueueItem(
                dequeued,
                anyWarnings || executors.Any(x => x.AnyWarnings)
                    ? QueueStatus.DataLoadCompletedPartially
                    : QueueStatus.DataLoadCompleted);

            DisposeScopedServices();

        }
        private async Task CatchAndLogException(Func<Task> func, Action onException)
        {
            try
            {
                await func();
            }
            catch (Exception e)
            {
                _logger.LogError(e.ToString());
                onException();
            }
        }

        private void DisposeScopedServices()
        {
            _queueSvc = null;
            _context.Dispose();
            _analysisSvc = null;
            _logBuffer = null;
        }

        /// <summary>
        /// Method exception handler
        /// </summary>
        public void OnException(Exception ex) => _logger.LogError(ex.Message);

        private async Task<(string error, DataSourceQueue result)> Dequeue()
        {
            DataSourceQueue queueItem;
            try
            {
                queueItem = await _queueSvc.Dequeue();
            }
            catch (Exception ex)
            {
                return (ex.Message, null);
            }
            return (null, queueItem);
        }

        private async Task ParseFile(DataSourceQueue queueItem, BlockingCollection<IReadOnlyDictionary<string, object>> tasks)
        {
            _logger.LogInformation("parsing queue entry #{0}", queueItem.Id);
            Stopwatch swParseFile = new Stopwatch();
            swParseFile.Start();
            IEnumerable<IReadOnlyDictionary<string, object>> parsed;
            try
            {
                switch (queueItem.DataSourceFileName)
                {
                    case string name when name.EndsWith(".xml", StringComparison.OrdinalIgnoreCase):
                        await FileParser.GetRawEntitiesFromXml(queueItem.DataSourcePath, queueItem.DataSource.VariablesMappingArray, tasks);
                        break;
                    case string name when name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase):
                        await FileParser.GetRawEntitiesFromCsv(
                            queueItem.DataSourcePath,
                            queueItem.DataSource.CsvSkipCount,
                            queueItem.DataSource.CsvDelimiter,
                            queueItem.DataSource.VariablesMappingArray, tasks);
                        break;
                    default:
                        //await CompleteParse("Unsupported type of file");
                        return;
                }
            }
            catch (Exception ex)
            {
                //await CompleteParse(ex.Message);
                return;
            }
            finally
            {
                swParseFile.Stop();
                tasks.CompleteAdding();
            }

            //IReadOnlyDictionary<string, object>[] parsedArr = parsed.ToArray();

            //if (parsedArr.Length == 0)
            //{
            //    await CompleteParse(Resource.UploadFileEmpty);
            //    return;
            //}

            //if (parsedArr.Any(x => x.Count == 0))
            //{
            //    await CompleteParse(Resource.FileHasEmptyUnit);
            //    return;
            //}

            //async Task CompleteParse(string parseError)
            //{
            //    swParseFile.Stop();
            //    if (parseError.HasValue())
            //    {
            //        _logger.LogInformation("finish queue item with error: {0}", parseError);
            //        await _queueSvc.FinishQueueItem(queueItem, QueueStatus.DataLoadFailed, parseError);
            //        return;
            //    }
            //}
        }

        private (string, (IReadOnlyDictionary<string, string[]>, string[] test)) AnalyzeUnit(IStatisticalUnit unit, DataSourceQueue queueItem)
        {
            if (queueItem.DataSource.DataSourceUploadType != DataSourceUploadTypes.StatUnits)
                return (null, (new Dictionary<string, string[]>(), new string[0]));

            AnalysisResult analysisResult;
            try
            {
                analysisResult = _analysisSvc.AnalyzeStatUnit(unit, queueItem.DataSource.AllowedOperations == DataSourceAllowedOperation.Alter, true, false);
            }
            catch (Exception ex)
            {
                return (ex.Message, (null, null));
            }
            return (null, (
                analysisResult.Messages,
                analysisResult.SummaryMessages?.ToArray() ?? Array.Empty<string>()));
        }

        /// <summary>
        /// Делает копию файла с удалением пустых строк
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        private async Task<string> MutateFileAsync(DataSourceQueue item)
        {
            var rawLines = await GetRawFileAsync(item);
            try
            {
                await WriteFileAsync(string.Join("\r\n", rawLines.Where(c => !string.IsNullOrEmpty(c))), item.DataSourcePath);
            }
            catch (Exception ex)
            {
                return ex.Message;
            }
            return string.Empty;
        }

        private async Task<string[]> GetRawFileAsync(DataSourceQueue item)
        {
            if (item.DataSource == null) throw new Exception(Resource.DataSourceNotFound);
            var i = item.DataSource.CsvSkipCount;
            string rawLines;
            if (!File.Exists(item.DataSourcePath)) throw new FileNotFoundException(Resource.FileDoesntExistOrInQueue);
            using (var stream = File.OpenRead(item.DataSourcePath))
            using (var reader = new StreamReader(stream))
            {
                while (--i == 0) await reader.ReadLineAsync();
                rawLines = await reader.ReadToEndAsync();
            }

            return rawLines.Split('\r', '\n');
        }

        private async Task WriteFileAsync(string csv, string path) => await File.WriteAllTextAsync(path, csv);
    }
}
