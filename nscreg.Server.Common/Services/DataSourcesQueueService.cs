using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System.Linq.Dynamic.Core;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Models.DataSourcesQueue;
using nscreg.Utilities.Enums;
using SearchQueryM = nscreg.Server.Common.Models.DataSourcesQueue.SearchQueryM;

namespace nscreg.Server.Common.Services
{
    public class DataSourcesQueueService
    {
        private readonly NSCRegDbContext _dbContext;
        private const string RootPath = "..";
        private const string UploadDir = "uploads";

        public DataSourcesQueueService(NSCRegDbContext ctx)
        {
            _dbContext = ctx;
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
            var orderRule = query.SortAscending ? "ASC" : "DESC";
            var filtered = _dbContext.DataUploadingLogs
                .Where(x => x.DataSourceQueueId == queueId)
                .OrderBy($"{query.SortBy} {orderRule}");

            var total = await filtered.CountAsync();
            var totalPages = (int)Math.Ceiling((double)total / query.PageSize);
            var skip = query.PageSize * Math.Abs(Math.Min(totalPages, query.Page) - 1);

            var result = await filtered
                .Skip(skip)
                .Take(query.PageSize)
                .AsNoTracking()
                .ToListAsync();

            return SearchVm<QueueLogVm>.Create(result.Select(QueueLogVm.Create), total);
        }

        public async Task<QueueLogDetailsVm> GetLogDetails(int logId)
            => QueueLogDetailsVm.Create(await _dbContext.DataUploadingLogs.FindAsync(logId));

        public async Task CreateAsync(IFormFileCollection files, UploadDataSourceVm data, string userId)
        {
            var today = DateTime.Now;
            var path = Path.Combine(
                Path.GetFullPath(RootPath),
                UploadDir,
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
    }
}
