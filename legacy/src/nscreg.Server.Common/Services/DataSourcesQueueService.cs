using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataSourcesQueue;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Linq.Dynamic.Core;
using System.Threading.Tasks;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using Newtonsoft.Json;
using Activity = nscreg.Data.Entities.Activity;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using SearchQueryM = nscreg.Server.Common.Models.DataSourcesQueue.SearchQueryM;
using AutoMapper;
using System.Reflection;

namespace nscreg.Server.Common.Services
{
    public class DataSourcesQueueService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly CreateService _createSvc;
        private readonly EditService _editSvc;
        private readonly string _rootPath;
        private readonly string _uploadDir;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly DeleteService _statUnitDeleteService;
        private readonly IElasticUpsertService _elasticService;
        private readonly ViewService _viewService;
        private readonly IMapper _mapper;

        public DataSourcesQueueService(NSCRegDbContext ctx,
            CreateService createSvc,
            EditService editSvc, DeleteService statUnitDeleteService,
            ServicesSettings config, IElasticUpsertService elasticService,
            DbMandatoryFields dbMandatoryFields, ViewService viewService, IMapper mapper)
        {
            _dbContext = ctx;
            _createSvc = createSvc;
            _editSvc = editSvc;
            _rootPath = config.RootPath;
            _uploadDir = config.UploadDir;
            _dbMandatoryFields = dbMandatoryFields;
            _statUnitDeleteService = statUnitDeleteService;
            _elasticService = elasticService;
            _viewService = viewService;
            _mapper = mapper;
        }

        public async Task<SearchVm<QueueVm>> GetAllDataSourceQueues(SearchQueryM query)
        {
            var sortBy = string.IsNullOrEmpty(query.SortBy)
                ? "Id"
                : query.SortBy;

            var orderRule = query.OrderByValue == OrderRule.Asc && !string.IsNullOrEmpty(query.SortBy)
                ? "ASC"
                : "DESC";

            var filtered = _dbContext.DataSourceQueues
                .Include(x => x.DataSource)
                .Include(x => x.User)
                .AsNoTracking();

            if (query.Status.HasValue)
                filtered = filtered.Where(x => x.Status == query.Status.Value);

            if (query.DateFrom.HasValue && query.DateTo.HasValue)
            {
                filtered = filtered.Where(x => x.StartImportDate >= query.DateFrom.Value &&
                                               x.StartImportDate <= query.DateTo.Value);
            }
            else
            {
                if (query.DateFrom.HasValue)
                    filtered = filtered.Where(x => x.StartImportDate >= query.DateFrom.Value);

                if (query.DateTo.HasValue)
                    filtered = filtered.Where(x => x.StartImportDate <= query.DateTo.Value);
            }

            filtered = filtered.OrderBy($"{sortBy} {orderRule}");

            var total = await filtered.CountAsync();

            var result = await filtered
                .Skip(Pagination.CalculateSkip(query.PageSize, query.Page, total))
                .Take(query.PageSize)
                .AsNoTracking()
                .ToListAsync();

            return SearchVm<QueueVm>.Create(result.Select(QueueVm.Create), total);
        }

        public async Task<SearchVm<QueueLogVm>> GetQueueLog(int queueId, PaginatedQueryM query)
        {
            var queue = await _dbContext.DataSourceQueues.Include(x => x.DataSource).FirstAsync(x => x.Id == queueId);
            switch (queue.DataSource.DataSourceUploadType)
            {
                case DataSourceUploadTypes.StatUnits:
                    return await GetQueueLogForStatUnitUpload(queueId, query);
                default:
                    throw new ArgumentOutOfRangeException();
            }
        }

        private async Task<SearchVm<QueueLogVm>> GetQueueLogForActivityUpload(int queueId, PaginatedQueryM query)
        {
            var orderBy = string.IsNullOrEmpty(query.SortBy) ? nameof(DataUploadingLog.Id) : query.SortBy;
            var orderRule = query.SortAscending ? "ASC" : "DESC";
            var filtered = _dbContext.DataUploadingLogs
                .Where(x => x.DataSourceQueueId == queueId && x.Status != DataUploadingLogStatuses.Done)
                .OrderBy($"{orderBy} {orderRule}")
                .GroupBy(x => x.TargetStatId);
            var total = await filtered.CountAsync();

            var result = (await filtered
                    .Skip(Pagination.CalculateSkip(query.PageSize, query.Page, total))
                    .Take(query.PageSize)
                    .AsNoTracking()
                    .ToListAsync())
                .Select(x => new DataUploadingLog
                {
                    DataSourceQueue = x.FirstOrDefault()?.DataSourceQueue,
                    EndImportDate = x.Select(y => y.EndImportDate).Max(),
                    StartImportDate = x.Select(y => y.StartImportDate).Max(),
                    TargetStatId = x.FirstOrDefault()?.TargetStatId,
                    StatUnitName = x.FirstOrDefault()?.StatUnitName,
                    Status = x.Any(y => y.Status == DataUploadingLogStatuses.Error)
                        ? DataUploadingLogStatuses.Error
                        : x.Any(y => y.Status == DataUploadingLogStatuses.Warning)
                            ? DataUploadingLogStatuses.Warning
                            : DataUploadingLogStatuses.Done,
                    Note = x.FirstOrDefault()?.Note,
                });

            return SearchVm<QueueLogVm>.Create(result.Select(QueueLogVm.Create), total);
        }

        private async Task<SearchVm<QueueLogVm>> GetQueueLogForStatUnitUpload(int queueId, PaginatedQueryM query)
        {
            var orderBy = string.IsNullOrEmpty(query.SortBy) ? nameof(DataUploadingLog.Id) : query.SortBy;
            var orderRule = query.SortAscending ? "ASC" : "DESC";
            var filtered = _dbContext.DataUploadingLogs
                .Where(x => x.DataSourceQueueId == queueId && x.Status != DataUploadingLogStatuses.Done)
                .OrderBy($"{orderBy} {orderRule}");

            var total = await filtered.CountAsync();

            var result = await filtered
                .Skip(Pagination.CalculateSkip(query.PageSize, query.Page, total))
                .Take(query.PageSize)
                .AsNoTracking()
                .ToListAsync();

            return SearchVm<QueueLogVm>.Create(result.Select(QueueLogVm.Create), total);
        }

        public async Task<QueueLogDetailsVm> GetLogDetails(int logId)
        {
            var logEntry = await _dbContext.DataUploadingLogs
                .Include(x => x.DataSourceQueue)
                .ThenInclude(x => x.DataSource)
                .FirstOrDefaultAsync(x => x.Id == logId);

            if (logEntry == null)
            {
                throw new NotFoundException(nameof(Resource.NotFoundMessage));
            }

            var metadata = await _viewService.GetViewModel(
                null,
                logEntry.DataSourceQueue.DataSource.StatUnitType,
                logEntry.DataSourceQueue.UserId,
                ActionsEnum.Edit);

            return QueueLogDetailsVm.Create(
                logEntry,
                metadata.StatUnitType,
                metadata.Properties,
                metadata.Permissions);
        }

        public async Task CreateAsync(IFormFileCollection files, UploadQueueItemVm data, string userId)
        {
            var uploadPath = GetUploadPath();
            EnsureDirectoryExists(uploadPath);

            try
            {
                foreach (var file in files)
                {
                    var filePath = SaveFileToDisk(file, uploadPath);
                    AddToQueue(file, filePath, data, userId);
                }

                await _dbContext.SaveChangesAsync();
            }
            catch (IOException e)
            {
                throw new BadRequestException(nameof(Resource.CantStoreFile), e);
            }
            catch (Exception e)
            {
                throw new Exception("An unexpected error occurred.", e);
            }
        }

        private string GetUploadPath()
        {
            var tempPath = Path.GetTempPath();
            return Path.Combine(
                tempPath,
                _uploadDir,
                Guid.NewGuid().ToString()
                );
        }

        private void EnsureDirectoryExists(string path)
        {
            if (!Directory.Exists(path))
            {
                Directory.CreateDirectory(path);
            }
        }

        private string SaveFileToDisk(IFormFile file, string uploadPath)
        {
            var filePath = Path.Combine(uploadPath, Guid.NewGuid().ToString());

            using var fileStream = new FileStream(filePath, FileMode.Create);
            file.CopyTo(fileStream);

            return filePath;
        }

        private void AddToQueue(IFormFile file, string filePath, UploadQueueItemVm data, string userId)
        {
            var today = DateTimeOffset.UtcNow;
            _dbContext.DataSourceQueues.Add(new DataSourceQueue
            {
                UserId = userId,
                DataSourcePath = filePath,
                DataSourceFileName = file.FileName,
                DataSourceId = data.DataSourceId,
                Description = data.Description,
                StartImportDate = today,
                Status = DataSourceQueueStatuses.InQueue,
            });
        }

        public async Task<Dictionary<string, string[]>> UpdateLog(int logId, string data, string userId)
        {
            var logEntry = await _dbContext.DataUploadingLogs
                .Include(l => l.DataSourceQueue)
                .ThenInclude(q => q.DataSource)
                .FirstOrDefaultAsync(l => l.Id == logId);
            if (logEntry == null) throw new BadRequestException(nameof(Resource.UploadLogNotFound));

            var type = logEntry.DataSourceQueue.DataSource.StatUnitType;
            var definitionWithRegId = new {RegId = 0};
            var hasId = JsonConvert.DeserializeAnonymousType(data, definitionWithRegId).RegId > 0;

            Task<Dictionary<string, string[]>> task;
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    task = hasId
                        ? _editSvc.EditLocalUnit(ParseModel<LocalUnitEditM>(), userId)
                        : _createSvc.CreateLocalUnit(ParseModel<LocalUnitCreateM>(), userId);
                    break;
                case StatUnitTypes.LegalUnit:
                    task = hasId
                        ? _editSvc.EditLegalUnit(ParseModel<LegalUnitEditM>(), userId)
                        : _createSvc.CreateLegalUnit(ParseModel<LegalUnitCreateM>(), userId);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    task = hasId
                        ? _editSvc.EditEnterpriseUnit(ParseModel<EnterpriseUnitEditM>(), userId)
                        : _createSvc.CreateEnterpriseUnit(ParseModel<EnterpriseUnitCreateM>(), userId);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(
                        $"Parameter `{nameof(data)}`: value of type `{type}` is not supported.");
            }

            var errors = await task;
            if (errors != null && errors.Any()) return errors;

            logEntry.Status = DataUploadingLogStatuses.Done;
            await _dbContext.SaveChangesAsync();

            return null;

            T ParseModel<T>() where T : StatUnitModelBase
            {
                var result = JsonConvert.DeserializeObject<T>(data);
                result.DataSource = logEntry.DataSourceQueue.DataSource.Name;
                return result;
            }
        }

        public async Task<IEnumerable<Activity>> GetActivityLogDetailsByStatId(int queueId, string statId)
        {
            var logEntries = await _dbContext.DataUploadingLogs
                .Where(x => x.DataSourceQueueId == queueId)
                .Where(x => x.TargetStatId == statId)
                .ToListAsync();
            var queue = await _dbContext.DataSourceQueues
                .Include(x => x.DataSource)
                .FirstAsync(x => x.Id == queueId);

            var deserializeMap = new Dictionary<StatUnitTypes, Func<string, StatisticalUnit>>()
            {
                [StatUnitTypes.LegalUnit] = JsonConvert.DeserializeObject<LegalUnit>,
                [StatUnitTypes.LocalUnit] = JsonConvert.DeserializeObject<LocalUnit>,
                [StatUnitTypes.EnterpriseUnit] = JsonConvert.DeserializeObject<EnterpriseUnit>

            };
            var activities = logEntries
                .Select(x => x.SerializedUnit)
                .Select(deserializeMap[queue.DataSource.StatUnitType])
                .Select(x => x.ActivitiesUnits.First().Activity);

           return activities;
        }

        /// <summary>
        /// Checks other logs of data source queue
        /// </summary>
        /// <param name="queueId">Id of data source queue</param>
        private bool QueueLogsExist(int queueId)
        {
            var existing = _dbContext.DataUploadingLogs.FirstOrDefault(log => log.DataSourceQueueId == queueId);
            return existing != null;
        }

        /// <summary>
        /// Data source queue delete method from db
        /// </summary>
        /// <param name="queueId">Id of data source queue</param>
        public async Task DeleteQueueById(int queueId)
        {
            var existing = await _dbContext.DataSourceQueues.FirstOrDefaultAsync(x => x.Id == queueId);
            if (existing == null) throw new NotFoundException(nameof(Resource.DataSourceQueueNotFound));
            _dbContext.DataSourceQueues.Remove(existing);
            await _dbContext.SaveChangesAsync();
        }

        /// <summary>
        /// Log delete method with clearing statistical units
        /// </summary>
        /// <param name="logId">Id of log</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteLog(DataUploadingLog log, string userId)
        {
            if (log == null)
                throw new NotFoundException(nameof(Resource.QueueLogNotFound));

            if (log.SerializedUnit != null)
            {
                dynamic jsonParsed = JsonConvert.DeserializeObject(log.SerializedUnit);
                int unitType = int.Parse(jsonParsed["unitType"].ToString());

                if (log.Status == DataUploadingLogStatuses.Done &&
                    log.StartImportDate != null)
                {
                    switch (unitType)
                    {
                        case (int)StatUnitTypes.LocalUnit:
                            await _statUnitDeleteService.DeleteLocalUnitFromDb(log.TargetStatId, userId, log.StartImportDate);
                            break;
                        case (int)StatUnitTypes.LegalUnit:
                            await _statUnitDeleteService.DeleteLegalUnitFromDb(log.TargetStatId, userId, log.StartImportDate);
                            break;
                        case (int)StatUnitTypes.EnterpriseUnit:
                            await _statUnitDeleteService.DeleteEnterpriseUnitFromDb(log.TargetStatId, userId, log.StartImportDate);
                            break;
                        default:
                            throw new NotFoundException(nameof(Resource.StatUnitTypeNotFound));
                    }
                }
            }
            _dbContext.DataUploadingLogs.Remove(log);
            await _dbContext.SaveChangesAsync();
        }

        private List<StatUnitTypes> GetUnitTypes(string statId, StatUnitTypes statUnitType)
        {
            var statUnitTypes = new List<StatUnitTypes>();
            var isContainDataSource = _dbContext.StatisticalUnits.AsNoTracking().First(x => x.StatId == statId && x.UnitType == statUnitType).DataSource != null;
            if (!isContainDataSource)
            {
                statUnitTypes.Add(statUnitType);
            }
            else
            {
                statUnitTypes.AddRange(_dbContext.StatisticalUnits.AsNoTracking().Where(x=>x.StatId == statId && x.DataSource != null).Select(x=>x.UnitType).ToList());
            }

            return statUnitTypes;
        }

        /// <summary>
        /// Log delete method, if data queue hasn`t other logs, this method will delete data queue too
        /// </summary>
        /// <param name="logId">Id of log</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteLog(int logId, string userId)
        {
            var existing = await _dbContext.DataUploadingLogs.FirstOrDefaultAsync(c => c.Id == logId);
            if (existing == null)
                throw new NotFoundException(nameof(Resource.QueueLogNotFound));

            await DeleteLog(existing, userId);

            if (!QueueLogsExist(existing.DataSourceQueueId))
                await DeleteQueueById(existing.DataSourceQueueId);

        }

        ///// <summary>
        ///// Data source queue delete method
        ///// </summary>
        ///// <param name="queueId">Id of data source queue</param>
        ///// <param name="userId">Id of user</param>
        //public async Task DeleteQueue(int queueId, string userId)
        //{
        //    var existing = await _dbContext.DataSourceQueues.FindAsync(queueId);
        //    if (existing == null) throw new NotFoundException(nameof(Resource.DataSourceQueueNotFound));
        //    var logs = _dbContext.DataUploadingLogs.Where(log => log.DataSourceQueueId == existing.Id).ToList();
        //    if (logs.Any())
        //    {
        //        await logs.ForEachAsync(log => DeleteLogById(log, userId));
        //    }
        //    await DeleteQueueById(existing.Id);
        //}

        /// <summary>
        /// Data source queue delete method
        /// </summary>
        /// <param name="queueId">Id of data source queue</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteQueue(int queueId, string userId)
        {
            var existing = await _dbContext.DataSourceQueues.FirstOrDefaultAsync(c => c.Id == queueId);
            if (existing == null) throw new NotFoundException(nameof(Resource.DataSourceQueueNotFound));
            var logs = await _dbContext.DataUploadingLogs.Where(log => log.DataSourceQueueId == existing.Id).ToListAsync();
            Dictionary<int, List<DataUploadingLog>> unitTypeDataUploadLogDict = new Dictionary<int, List<DataUploadingLog>>();
            if (logs.Any())
            {
                logs.ForEach(x =>
                {
                    if (x.Status == DataUploadingLogStatuses.Done && x.StartImportDate != null && x.SerializedUnit != null)
                    {
                        dynamic unit = JsonConvert.DeserializeObject(x.SerializedUnit);
                        int key = int.Parse(unit["unitType"].ToString());
                        if (unitTypeDataUploadLogDict.ContainsKey(key))
                            unitTypeDataUploadLogDict[key].Add(x);
                        else
                        {
                            unitTypeDataUploadLogDict.Add(int.Parse(unit["unitType"].ToString()), new List<DataUploadingLog> { x });
                        }
                    }
                });
                if (unitTypeDataUploadLogDict.TryGetValue((int)StatUnitTypes.LocalUnit, out var uploadLocalUnitsLogs))
                    await _statUnitDeleteService.DeleteRangeLocalUnitsFromDb(uploadLocalUnitsLogs.Select(x => x.TargetStatId).ToList(), userId, logs.Select(x => x.StartImportDate).OrderBy(c => c.Value).First());

                if(unitTypeDataUploadLogDict.TryGetValue((int)StatUnitTypes.LegalUnit, out var uploadLegalUnitsLogs))
                    await _statUnitDeleteService.DeleteRangeLegalUnitsFromDb(uploadLegalUnitsLogs.Select(x => x.TargetStatId).ToList(), userId, logs.Select(x => x.StartImportDate).OrderBy(c => c.Value).First());

                if (unitTypeDataUploadLogDict.TryGetValue((int)StatUnitTypes.EnterpriseUnit, out var uploadEnterprisesLogs))
                    await _statUnitDeleteService.DeleteRangeEnterpriseUnitsFromDb(uploadEnterprisesLogs.Select(x => x.TargetStatId).ToList(), userId, logs.Select(x => x.StartImportDate).OrderBy(c => c.Value).First());
            }
            await DeleteQueueById(existing.Id);
        }
    }
}
