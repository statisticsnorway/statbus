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
using System.Globalization;
using ServiceStack;
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
        private readonly int _dbLogBufferMaxCount;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private NSCRegDbContext _context;
        private readonly bool _personsGoodQuality;
       
        public QueueJob(
            int dequeueInterval,
            ILogger logger,
            StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields,
            ValidationSettings validationSettings, int bufferLogMaxCount, bool personsGoodQuality)
        {
            _personsGoodQuality = personsGoodQuality;
            _logger = logger;
            Interval = dequeueInterval;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _dbMandatoryFields = dbMandatoryFields;
            _validationSettings = validationSettings;
            _dbLogBufferMaxCount = bufferLogMaxCount;
        }

        private void AddScopedServices()
        {
            var dbContextHelper = new DbContextHelper();
            _context = dbContextHelper.CreateDbContext(new string[] { });
            _queueSvc = new QueueService(_context);
            _logBuffer = new DbLogBuffer(_context, _dbLogBufferMaxCount);
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

            var dataAccessService = new DataAccessService(_context);
            if (dataAccessService.CheckWritePermissions(dequeued.UserId, dequeued.DataSource.StatUnitType))
            {
                var message = $"User doesn't have write permission for {dequeued.DataSource.StatUnitType}";
                _logger.LogInformation("finish queue item with error: {0}", message);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, message);
            }

            _logger.LogInformation("mutation queue file #{0}", dequeued.Id);

            var mutateError = await MutateFileAsync(dequeued);
            if (mutateError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", mutateError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, mutateError);
            }

            var executor = new ImportExecutor(_statUnitAnalysisRules, _dbMandatoryFields, _validationSettings, _logger, _logBuffer, _personsGoodQuality);

            //var swParse = new Stopwatch();
            var (parseError, parsed) = await ParseFile(dequeued/*, swParse*/);
           
            if (parseError.HasValue())
            {
                _logger.LogInformation("finish queue item with error: {0}", parseError);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, parseError);
                return;
            }

            _logger.LogInformation("parsed {0} entities", parsed.Length);
            var anyWarnings = false;

            await CatchAndLogException(async () => await executor.Start(dequeued, parsed), () => anyWarnings = true);
            await CatchAndLogException(async () => await _logBuffer.FlushAsync(), () => anyWarnings = true);
           
            await _queueSvc.FinishQueueItem(
                dequeued,
                anyWarnings || executor.AnyWarnings
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

        private async Task<(string error, IReadOnlyDictionary<string, object>[] result)> ParseFile(DataSourceQueue queueItem/*, Stopwatch swParseFile*/)
        {
            _logger.LogInformation("parsing queue entry #{0}", queueItem.Id);
            IEnumerable<IReadOnlyDictionary<string, object>> parsed;
            // swParseFile.Start();
            try
            {
                switch (queueItem.DataSourceFileName)
                {
                    case string name when name.EndsWith(".xml", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromXml(queueItem.DataSourcePath,
                            queueItem.DataSource.VariablesMappingArray);
                        break;
                    case string name when name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromCsv(
                            queueItem.DataSourcePath,
                            queueItem.DataSource.CsvSkipCount,
                            queueItem.DataSource.CsvDelimiter,
                            queueItem.DataSource.VariablesMappingArray);
                        break;
                    default:
                         return ("Unsupported type of file", null);
                }
            }
            catch (Exception ex)
            {
                return (ex.Message, null);
            }
            var parsedArr = parsed.ToArray();

            if (parsedArr.Length == 0)
            {
                return (Resource.UploadFileEmpty, parsedArr);
            }

            if (parsedArr.Any(x => x.Count == 0))
            {
                return (Resource.FileHasEmptyUnit, parsedArr);
            }
            return (null, parsedArr);
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
               await File.WriteAllTextAsync(item.DataSourcePath, string.Join("\r\n", rawLines.Where(c => !string.IsNullOrEmpty(c))));
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
    }
}
