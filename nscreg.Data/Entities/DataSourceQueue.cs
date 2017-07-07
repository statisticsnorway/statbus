using System;
using System.Collections.Generic;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class DataSourceQueue
    {
        public int Id { get; set; }
        public DateTime? StartImportDate { get; set; }
        public DateTime? EndImportDate { get; set; }
        public string DataSourcePath { get; set; }
        public string DataSourceFileName { get; set; }
        public string Description { get; set; }
        public DataSourceQueueStatuses Status { get; set; }
        public int DataSourceId { get; set; }
        public virtual DataSource DataSource { get; set; }
        public virtual ICollection<DataUploadingLog> DataUploadingLogs { get; set; }
        public string UserId { get; set; }
        public virtual User User { get; set; }

    }
}

