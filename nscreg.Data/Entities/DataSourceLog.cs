using System;
using System.Collections.Generic;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class DataSourceLog
    {
        public int Id { get; set; }
        public DateTime StartImportDate { get; set; }
        public DateTime EndImportDate { get; set; }
        public byte[] ImportedFile { get; set; }
        public string DataSourceFileName { get; set; }
        public string Description { get; set; }
        public DataSourceLogStatuses Status { get; set; }
        public int DataSourceId { get; set; }
        public DataSource DataSource { get; set; }
        public List<DataUploadingLog> DataUploadingLogs { get; set; }

    }
}

