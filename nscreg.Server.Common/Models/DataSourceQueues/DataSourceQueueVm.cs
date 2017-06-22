using System;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.DataSourceQueues
{
    public class DataSourceQueueVm
    {
        private DataSourceQueueVm(DataSourceQueue item)
        {
            Id = item.Id;
            FileName = item.DataSourceFileName;
            DataSourceTemplateName = item.DataSource.Name;
            UploadDateTime = item.StartImportDate;
            UserName = item.User.Name;
            Status = (int)item.Status; 
        }

        public static DataSourceQueueVm Create(DataSourceQueue item) => new DataSourceQueueVm(item);

        public int Id { get; }
        public string FileName { get; }
        public string DataSourceTemplateName { get; }
        public DateTime UploadDateTime { get; }
        public string UserName { get; }
        public int Status { get; }
    }
}
