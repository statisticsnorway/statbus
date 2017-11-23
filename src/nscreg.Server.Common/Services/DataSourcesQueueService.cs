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
using nscreg.Utilities.Configuration;
using Newtonsoft.Json;
using SearchQueryM = nscreg.Server.Common.Models.DataSourcesQueue.SearchQueryM;

namespace nscreg.Server.Common.Services
{
    public class DataSourcesQueueService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly CreateService _createSvc;
        private readonly EditService _editSvc;
        private readonly string _rootPath;
        private readonly string _uploadDir;

        public DataSourcesQueueService(NSCRegDbContext ctx, CreateService createSvc, EditService editSvc, ServicesSettings config)
        {
            _dbContext = ctx;
            _createSvc = createSvc;
            _editSvc = editSvc;
            _rootPath = config.RootPath;
            _uploadDir = config.UploadDir;
        }

        public async Task<SearchVm<QueueVm>> GetAllDataSourceQueues(SearchQueryM query)
        {
            var sortBy = string.IsNullOrEmpty(query.SortBy)
                ? "Id"
                : query.SortBy;

            var orderRule = query.OrderByValue == OrderRule.Asc
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
            var totalPages = (int) Math.Ceiling((double) total / query.PageSize);
            var skip = query.PageSize * Math.Abs(Math.Min(totalPages, query.Page) - 1);

            var result = await filtered
                .Skip(skip)
                .Take(query.PageSize)
                .ToListAsync();

            return SearchVm<QueueVm>.Create(result.Select(QueueVm.Create), total);
        }

        public async Task<SearchVm<QueueLogVm>> GetQueueLog(int queueId, PaginatedQueryM query)
        {
            var orderBy = string.IsNullOrEmpty(query.SortBy) ? nameof(DataUploadingLog.Id) : query.SortBy;
            var orderRule = query.SortAscending ? "ASC" : "DESC";
            var filtered = _dbContext.DataUploadingLogs
                .Where(x => x.DataSourceQueueId == queueId)
                .OrderBy($"{orderBy} {orderRule}");

            var total = await filtered.CountAsync();
            var totalPages = (int) Math.Ceiling((double) total / query.PageSize);
            var skip = query.PageSize * Math.Abs(Math.Min(totalPages, query.Page) - 1);

            var result = await filtered
                .Skip(skip)
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

            var metadata = await new ViewService(_dbContext).GetViewModel(
                null,
                logEntry.DataSourceQueue.DataSource.StatUnitType,
                logEntry.DataSourceQueue.UserId);

            return QueueLogDetailsVm.Create(
                logEntry,
                metadata.StatUnitType,
                metadata.Properties,
                metadata.DataAccess.GetReadablePropNames()); //TODO FIX THIS!!!!!!
        }

        public async Task CreateAsync(IFormFileCollection files, UploadQueueItemVm data, string userId)
        {
            var today = DateTime.Now;
            var path = Path.Combine(
                Path.GetFullPath(_rootPath),
                _uploadDir,
                today.Year.ToString(),
                today.Month.ToString(),
                today.Day.ToString());
            try
            {
                Directory.CreateDirectory(path);
                foreach (var file in files)
                {
                    var filePath = Path.Combine(path, Guid.NewGuid().ToString());
                    using (var fileStream = new FileStream(filePath, FileMode.Create))
                    {
                        await file.CopyToAsync(fileStream);
                        _dbContext.DataSourceQueues.Add(new DataSourceQueue
                        {
                            UserId = userId,
                            DataSourcePath = filePath,
                            DataSourceFileName = file.FileName,
                            DataSourceId = data.DataSourceId,
                            Description = data.Description,
                            StartImportDate = today,
                            EndImportDate = DateTime.Now,
                            Status = DataSourceQueueStatuses.InQueue,
                        });
                    }
                }
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.CantStoreFile), e);
            }
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
                        $"Parameter `{nameof(data)}`: value of type `{type.ToString()}` is not supported.");
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
    }
}
