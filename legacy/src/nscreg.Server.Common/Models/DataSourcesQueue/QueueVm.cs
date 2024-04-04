using System;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// View queue model
    /// </summary>
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
            Note = item.Note;
        }

        /// <summary>
        /// Method of creating a view of the queue model
        /// </summary>
        /// <param name="item">item</param>
        /// <returns></returns>
        public static QueueVm Create(DataSourceQueue item) => new QueueVm(item);

        public string Note { get; set; }
        public int Id { get; }
        public string FileName { get; }
        public string DataSourceTemplateName { get; }
        public DateTimeOffset? UploadDateTime { get; }
        public string UserName { get; }
        public int Status { get; }
    }
}
