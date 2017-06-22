using System;
using System.Collections.Generic;
using System.Threading;
using nscreg.Data;
using nscreg.Server.DataUploadSvc.Interfaces;
using nscreg.Services.DataSources;
using nscreg.Data.Entities;

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
            //TODO: Dequeue Batch and update status in single transaction
            // Process each of works and set result status
            var item = await _svc.Dequeue();
            DataSource dataSource;
            IEnumerable<Dictionary<string, string>> rawEntities;
            if (item.DataSourceFileName.EndsWith(".xml", StringComparison.Ordinal))
            {
                dataSource = item.DataSource;
                var handler = await HandleQueueItem.CreateXmlHandler(
                    item.DataSourceFileName,
                    dataSource.StatUnitType,
                    dataSource.AllowedOperations,
                    dataSource.Priority,
                    dataSource.VariablesMapping,
                    dataSource.Restrictions);
                rawEntities = handler.RawEntities;
            }
            else
            {
                dataSource = item.DataSource;
                var handler = await HandleQueueItem.CreateCsvHandler(
                    item.DataSourceFileName,
                    dataSource.StatUnitType,
                    dataSource.AllowedOperations,
                    dataSource.Priority,
                    dataSource.VariablesMapping,
                    dataSource.Restrictions);
                rawEntities = handler.RawEntities;
            }
            // rawEntities.ForEach?
        }

        public void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
