using System;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class DataUploadingLog
    {
        public int Id { get; set; }
        public DateTime StartImportDate { get; set; }
        public DateTime EndImportDate { get; set; }
        public string StatUnitId { get; set; } //OKPO + Name or the same.How to correct identify StatUnit(???)
        public string StatUnitName { get; set; }
        public StatUnitTypes StatUnitType { get; set; }
        public int DataSourceQueueId { get; set; }
        public DataUploadingLogStatuses Status { get; set; }
        public virtual DataSourceQueue DataSourceQueue { get; set; }
    }
}
