using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ModelGeneration;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// Вью модель подробной очереди журнала
    /// </summary>
    public class QueueLogDetailsVm
    {
        private QueueLogDetailsVm(
            DataUploadingLog item,
            StatUnitTypes statUnitType,
            PropertyMetadataBase[] properties,
            ICollection<string> dataAccess)
        {
            Id = item.Id;
            Started = item.StartImportDate;
            Ended = item.EndImportDate;
            StatId = item.TargetStatId;
            Name = item.StatUnitName;
            Unit = item.SerializedUnit;
            Status = item.Status;
            Note = item.Note;
            Errors = item.ErrorMessages;
            Summary = item.SummaryMessages;
            StatUnitType = statUnitType;
            Properties = properties;
            DataAccess = dataAccess;
        }

        /// <summary>
        /// Метод создания вью модели подробной очереди журнала 
        /// </summary>
        /// <param name="item">Единица очереди журнала</param>
        /// <param name="statUnitType">Тип стат. единицы</param>
        /// <param name="properties">Свойства метада</param>
        /// <param name="dataAccess">Правила доступа данных</param>
        /// <returns></returns>
        public static QueueLogDetailsVm Create(
            DataUploadingLog item,
            StatUnitTypes statUnitType,
            PropertyMetadataBase[] properties,
            ICollection<string> dataAccess)
            => new QueueLogDetailsVm(item, statUnitType, properties, dataAccess);

        public int Id { get; }
        public DateTime? Started { get; }
        public DateTime? Ended { get; }
        public string StatId { get; }
        public string Name { get; }
        public string Unit { get; }
        public DataUploadingLogStatuses Status { get; }
        public string Note { get; }
        public Dictionary<string, IEnumerable<string>> Errors { get; }
        public IEnumerable<string> Summary { get; }
        public StatUnitTypes StatUnitType { get; }
        public PropertyMetadataBase[] Properties { get; }
        public ICollection<string> DataAccess { get; }
    }
}
