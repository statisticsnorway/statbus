using System;
using System.Collections.Generic;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity data source queue
    /// </summary>
    public class DataSourceQueue
    {
        public int Id { get; set; }
        public DateTimeOffset? StartImportDate { get; set; }
        public DateTimeOffset? EndImportDate { get; set; }
        public string DataSourcePath { get; set; }
        public string DataSourceFileName { get; set; }
        public string Description { get; set; }
        public DataSourceQueueStatuses Status { get; set; }
        public string Note { get; set; }
        public int DataSourceId { get; set; }
        public virtual DataSource DataSource { get; set; }
        public virtual ICollection<DataUploadingLog> DataUploadingLogs { get; set; }
        public string UserId { get; set; }
        public int SkipLinesCount { get; set; }
        public virtual User User { get; set; }
    }
}
