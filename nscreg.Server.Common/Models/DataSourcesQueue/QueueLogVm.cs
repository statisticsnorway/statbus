using System;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
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

        public static QueueLogVm Create(DataUploadingLog item) => new QueueLogVm(item);

        public int Id { get; }
        public DateTime? Started { get; }
        public DateTime? Ended { get; }
        public string StatId { get; }
        public string Name { get; }
        public DataUploadingLogStatuses Status { get; }
        public string Note { get; }
    }
}
