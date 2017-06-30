using System;
using System.Collections.Generic;
using System.Threading;
using nscreg.Data;
using nscreg.Server.DataUploadSvc.Interfaces;
using nscreg.Services.DataSources;
using static nscreg.Services.DataSources.FileParser;

namespace nscreg.Server.DataUploadSvc.Jobs
{
    internal class QueueJob : IJob
    {
        public int Interval { get; }
        private readonly QueueService _svc;

        public QueueJob(NSCRegDbContext ctx, int dequeueInterval)
        {
            Interval = dequeueInterval;
            _svc = new QueueService(ctx);
        }

        public async void Execute(CancellationToken cancellationToken)
        {
            // take file from queue
            var queueItem = await _svc.Dequeue();

            // parse file
            IEnumerable<IReadOnlyDictionary<string, string>> rawEntities;
            switch (queueItem.DataSourceFileName)
            {
                case var str when str.EndsWith(".xml", StringComparison.Ordinal):
                    rawEntities = await GetRawEntitiesFromXml(queueItem.DataSourceFileName);
                    break;
                case var str when str.EndsWith(".csv", StringComparison.Ordinal):
                    rawEntities = await GetRawEntitiesFromCsv(queueItem.DataSourceFileName);
                    break;
                default:
                    // TODO: throw excetion if unknown file type?
                    throw new Exception("unknown data source type");
            }

            // parse entities
            foreach (var rawEntity in rawEntities)
            {
                // process unit
                await _svc.ProcessRawEntity(rawEntity, queueItem.DataSource);
            }
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
