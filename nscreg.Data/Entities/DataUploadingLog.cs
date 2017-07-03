using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class DataUploadingLog
    {
        public int Id { get; set; }
        public DateTime StartImportDate { get; set; }
        public DateTime EndImportDate { get; set; }
        public string TargetStatId { get; set; }
        public string StatUnitName { get; set; }
        public string SerializedUnit { get; set; }
        public int DataSourceQueueId { get; set; }
        public DataUploadingLogStatuses Status { get; set; }
        public string Note { get; set; }
        public virtual DataSourceQueue DataSourceQueue { get; set; }
    }
}
