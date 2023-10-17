using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.DataSources
{
    public class DbLogBuffer
    {
        private List<DataUploadingLog> Buffer { get; set; }

        private readonly NSCRegDbContext _context;
        public  readonly int MaxCount;
        public DbLogBuffer(NSCRegDbContext context, int maxCount)
        {
            Buffer = new List<DataUploadingLog>();
            _context = context;
            MaxCount = maxCount;
        }
        public async Task LogUnitUpload(DataSourceQueue queue,
            string rawUnit,
            DateTime? started,
            StatisticalUnit unit,
            DataUploadingLogStatuses status,
            string note,
            IReadOnlyDictionary<string, string[]> messages,
            IEnumerable<string> summaryMessages)
        {
            var logEntry = new DataUploadingLog
            {
                DataSourceQueueId = queue.Id,
                StartImportDate = started,
                EndImportDate = DateTime.Now,
                SerializedRawUnit = rawUnit,
                Status = status,
                Note = note,
                Errors = JsonConvert.SerializeObject(messages ?? new Dictionary<string, string[]>()),
                Summary = JsonConvert.SerializeObject(summaryMessages ?? Array.Empty<string>()),
            };
            if (unit != null)
            {
                logEntry.TargetStatId = unit.StatId;
                logEntry.StatUnitName = unit.Name;
                logEntry.SerializedUnit = JsonConvert.SerializeObject(unit, new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), ReferenceLoopHandling = ReferenceLoopHandling.Ignore });
            }

            Buffer.Add(logEntry);
            if(messages != null  && messages.Count > 0)
            {
                queue.SkipLinesCount += 1;
            }
            _context.Entry(queue).State = EntityState.Modified;
            await _context.SaveChangesAsync();
            if (Buffer.Count >= MaxCount)
            {
                await FlushAsync();
            }
        }
        /// <summary>
        /// Flushes buffer to database
        /// </summary>
        /// <returns></returns>
        public async Task FlushAsync()
        {
            await _context.DataUploadingLogs.AddRangeAsync(Buffer);
            await _context.SaveChangesAsync();
            Buffer.Clear();
        }

    }
}
