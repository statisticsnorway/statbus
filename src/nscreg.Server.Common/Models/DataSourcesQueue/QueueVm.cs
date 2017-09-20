using System;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    public class QueueVm
    {
        private QueueVm(DataSourceQueue item)
        {
            Id = item.Id;
            FileName = item.DataSourceFileName;
            DataSourceTemplateName = item.DataSource.Name;
            UploadDateTime = item.StartImportDate;
            UserName = item.User.Name;
            Status = (int)item.Status; 
        }

        public static QueueVm Create(DataSourceQueue item) => new QueueVm(item);

        public int Id { get; }
        public string FileName { get; }
        public string DataSourceTemplateName { get; }
        public DateTime? UploadDateTime { get; }
        public string UserName { get; }
        public int Status { get; }
    }
}
