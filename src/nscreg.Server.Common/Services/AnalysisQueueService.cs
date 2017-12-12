using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Models.AnalysisQueue;

namespace nscreg.Server.Common.Services
{
    public class AnalysisQueueService
    {
        private readonly NSCRegDbContext _context;

        public AnalysisQueueService(NSCRegDbContext context)
        {
            _context = context;
        }

        public async Task<AnalysisQueueListModel> GetAsync(SearchQueryModel filter)
        {
            IQueryable<AnalysisQueue> query = _context.AnalysisQueues.Include(x => x.User);

            if (filter.DateFrom.HasValue)
                query = query.Where(x => x.UserStartPeriod >= filter.DateFrom.Value);

            if (filter.DateTo.HasValue)
                query = query.Where(x => x.UserEndPeriod <= filter.DateTo.Value);

            var total = query.Count();
            var result = await query
                .Skip(filter.PageSize * (filter.Page - 1))
                .Take(filter.PageSize)
                .ToListAsync();

            return new AnalysisQueueListModel
            {
                TotalCount = total,
                CurrentPage = filter.Page,
                Items = Mapper.Map<IList<AnalysisQueueModel>>(result ?? new List<AnalysisQueue>()),
                PageSize = filter.PageSize,
                TotalPages = (int) Math.Ceiling((double) total / filter.PageSize)
            };
        }

        public async Task<AnalysisQueue> CreateAsync(AnalisysQueueCreateModel data, string userId)
        {
            var domain = Mapper.Map<AnalysisQueue>(data);
            domain.UserId = userId;
            _context.AnalysisQueues.Add(domain);
            await _context.SaveChangesAsync();
            return domain;
        }
    }
}
