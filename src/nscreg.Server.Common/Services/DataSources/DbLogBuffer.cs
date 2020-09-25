using System;
using System.Collections.Generic;
using System.Threading.Tasks;
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
        public DbLogBuffer(NSCRegDbContext context, int maxCount = 100)
        {
            Buffer = new List<DataUploadingLog>();
            _context = context;
            MaxCount = maxCount;
        }
        public async Task LogUnitUpload(int queueItemId,
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
                DataSourceQueueId = queueItemId,
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
                logEntry.SerializedUnit = JsonConvert.SerializeObject(unit, new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver() });
            }

            Buffer.Add(logEntry);

            if (Buffer.Count >= MaxCount)
            {
                await Flush();
            }
        }

        public async Task Flush()
        {
            _context.DataUploadingLogs.AddRange(Buffer);
            await _context.SaveChangesAsync();
            Buffer.Clear();
        }

    }
}
