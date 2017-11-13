using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using Newtonsoft.Json;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность журнал загрузки данных
    /// </summary>
    public class DataUploadingLog
    {
        public int Id { get; set; }
        public DateTime? StartImportDate { get; set; }
        public DateTime? EndImportDate { get; set; }
        public string TargetStatId { get; set; }
        public string StatUnitName { get; set; }
        public string SerializedUnit { get; set; }
        public int DataSourceQueueId { get; set; }
        public DataUploadingLogStatuses Status { get; set; }
        public string Note { get; set; }
        public string Errors { get; set; }
        public string Summary { get; set; }

        public Dictionary<string, IEnumerable<string>> ErrorMessages =>
            JsonConvert.DeserializeObject<Dictionary<string, IEnumerable<string>>>(Errors);

        public IEnumerable<string> SummaryMessages => JsonConvert.DeserializeObject<IEnumerable<string>>(Summary);

        public virtual DataSourceQueue DataSourceQueue { get; set; }
    }
}
