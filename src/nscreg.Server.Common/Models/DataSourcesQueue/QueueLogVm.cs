using System;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// View log queue model
    /// </summary>
    public class QueueLogVm
    {
        private QueueLogVm(DataUploadingLog item)
        {
            Id = item.Id;
            Started = item.StartImportDate;
            Ended = item.EndImportDate;
            StatId = item.TargetStatId;
            Name = item.StatUnitName;
            Status = item.Status;
            Note = item.Note;
        }

        /// <summary>
        /// Method for creating a view of a log queue model
        /// </summary>
        /// <param name="item">item</param>
        /// <returns></returns>
        public static QueueLogVm Create(DataUploadingLog item) => new QueueLogVm(item);

        public int Id { get; }
        public DateTimeOffset? Started { get; }
        public DateTimeOffset? Ended { get; }
        public string StatId { get; }
        public string Name { get; }
        public DataUploadingLogStatuses Status { get; }
        public string Note { get; }
    }
}
