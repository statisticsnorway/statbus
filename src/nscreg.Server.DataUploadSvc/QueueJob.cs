using AutoMapper;
using Microsoft.EntityFrameworkCore.Internal;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.ServicesUtils.Interfaces;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using ServiceStack;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Resources;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using QueueStatus = nscreg.Data.Constants.DataSourceQueueStatuses;

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
        private readonly int _bufferMaxCount;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly ValidationSettings _validationSettings;
        private NSCRegDbContext _context;
        private readonly bool _personsGoodQuality;
        private readonly int _elementsForRecreateContext;
        private readonly IMapper _mapper;
        private readonly DataAccessService _dataAccessService;
        private readonly ImportExecutor _importExecutor;

        public QueueJob( int dequeueInterval, ILogger logger, StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields dbMandatoryFields, ValidationSettings validationSettings,
            int bufferMaxCount, bool personsGoodQuality, int elementsForRecreateContext,
            IMapper mapper, DataAccessService dataAccessService, ImportExecutor importExecutor)
        {
            _personsGoodQuality = personsGoodQuality;
            _logger = logger;
            Interval = dequeueInterval;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _dbMandatoryFields = dbMandatoryFields;
            _validationSettings = validationSettings;
            _bufferMaxCount = bufferMaxCount;
            _elementsForRecreateContext = elementsForRecreateContext;
            _mapper = mapper;
            _dataAccessService = dataAccessService;
            _importExecutor = importExecutor;
        }

        private void AddScopedServices()
        {
            var dbContextHelper = new DbContextHelper();
            _context = dbContextHelper.CreateDbContext(new string[] { });
            _queueSvc = new QueueService(_context);
            _logBuffer = new DbLogBuffer(_context, _bufferMaxCount);
            
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
            try
            {
                //To wait for the elastic service to start
                await Task.Delay(15000);
                await new ElasticService(_context, _mapper).CheckElasticSearchConnection();
            }
            catch (Exception ex)
            {
                _logger.LogError("finish queue item with error: {0}", Resource.ElasticSearchIsDisable);
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, ex.Message);
                return;
            }

            if (_dataAccessService.CheckWritePermissions(dequeued.UserId, dequeued.DataSource.StatUnitType))
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
                return;
            }

            //var swParse = new Stopwatch();
            var (parseError, parsed, problemLine) = await ParseFile(dequeued/*, swParse*/);
           
            if (parseError.HasValue())
            {
                _logger.LogError("finish queue item with error: {0}", parseError);
                if (!string.IsNullOrEmpty(problemLine))
                    _logger.LogError($"Possible problem line:\n{problemLine}");
                await _queueSvc.FinishQueueItem(dequeued, QueueStatus.DataLoadFailed, parseError);
                return;
            }

            _logger.LogInformation("parsed {0} entities", parsed.Length);
            var anyWarnings = false;
            var exceptionMessage = string.Empty; 
            await CatchAndLogException(async () => await _importExecutor.Start(dequeued, parsed, _bufferMaxCount), ex =>
            {
                anyWarnings = true;
                exceptionMessage = ex;
            });
            await CatchAndLogException(async () => await _logBuffer.FlushAsync(), ex =>
            {
                anyWarnings = true;
                exceptionMessage = ex;
            });
           
            await _queueSvc.FinishQueueItem(
                dequeued,
                anyWarnings || _importExecutor.AnyWarnings
                    ? QueueStatus.DataLoadCompletedPartially
                    : QueueStatus.DataLoadCompleted, exceptionMessage);

            DisposeScopedServices();

        }
        private async Task CatchAndLogException(Func<Task> func, Action<string> onException)
        {
            try
            {
                await func();
            }
            catch (Exception e)
            {
                _logger.LogError(e.ToString());
                onException(e.Message);
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

        private async Task<(string error, IReadOnlyDictionary<string, object>[] result, string problemLine)> ParseFile(DataSourceQueue queueItem/*, Stopwatch swParseFile*/)
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
                            queueItem.DataSource.VariablesMappingArray, queueItem.SkipLinesCount);
                        break;
                    case string name when name.EndsWith(".csv", StringComparison.OrdinalIgnoreCase):
                        parsed = await FileParser.GetRawEntitiesFromCsv(
                            queueItem.DataSourcePath,
                            queueItem.DataSource.CsvDelimiter,
                            queueItem.DataSource.VariablesMappingArray,
                            queueItem.SkipLinesCount);
                        break;
                    default:
                         return ("Unsupported type of file", null, null);
                }
            }
            catch (Exception ex)
            {
                return (ex.Message, null, ex.Data["ProblemLine"] as string);
            }
            var parsedArr = parsed.ToArray();

            if (parsedArr.Length == 0)
            {
                return (Resource.UploadFileEmpty, parsedArr,null);
            }

            if (parsedArr.Any(x => x.Count == 0))
            {
                return (Resource.FileHasEmptyUnit, parsedArr, null);
            }
            return (null, parsedArr, null);
        }
        /// <summary>
        /// Делает копию файла с удалением пустых строк
        /// </summary>
        /// <param name="item"></param>
        /// <returns></returns>
        private async Task<string> MutateFileAsync(DataSourceQueue item)
        {
            var rawLines = (await GetRawFileAsync(item))
                .Select(x => x.EndsWith(item.DataSource.CsvDelimiter)
                ? x.Substring(0, x.Length - 1) : x).ToArray(); //Remove the csv delimiter at the end of the line
            try
            {
               await File.WriteAllTextAsync(item.DataSourcePath,
                   string.Join("\r\n", rawLines.Where(c => !string.IsNullOrEmpty(c))), encoding: Encoding.UTF8);
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
            string rawLines;
            if (!File.Exists(item.DataSourcePath)) throw new FileNotFoundException(Resource.FileDoesntExistOrInQueue);
            using (var stream = File.OpenRead(item.DataSourcePath))
            using (var reader = new StreamReader(stream, encoding: Encoding.UTF8))
            {
                rawLines = await reader.ReadToEndAsync();
            }

            return rawLines.Split('\r', '\n');
        }
    }
}
