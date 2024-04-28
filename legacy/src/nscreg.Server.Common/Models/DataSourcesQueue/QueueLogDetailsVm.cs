using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.ModelGeneration;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// View model of the detailed log queue
    /// </summary>
    public class QueueLogDetailsVm
    {
        private QueueLogDetailsVm(
            DataUploadingLog item,
            StatUnitTypes statUnitType,
            IEnumerable<PropertyMetadataBase> properties,
            IEnumerable<Permission> permissions)
        {
            Id = item.Id;
            Started = item.StartImportDate;
            Ended = item.EndImportDate;
            StatId = item.TargetStatId;
            Name = item.StatUnitName;
            Unit = item.SerializedUnit ?? "{}";
            RawUnit = item.SerializedRawUnit ?? "{}";
            Status = item.Status;
            Note = item.Note;
            Errors = item.ErrorMessages;
            Summary = item.SummaryMessages;
            StatUnitType = statUnitType;
            Properties = properties;
            Permissions = permissions;
        }

        /// <summary>
        ///Method for creating a view model for a detailed log queue
        /// </summary>
        /// <param name="item">item/param>
        /// <param name="statUnitType">stat unit type</param>
        /// <param name="properties">propertiesа</param>
        /// <param name="permissions">permissions</param>
        /// <returns></returns>
        public static QueueLogDetailsVm Create(
            DataUploadingLog item,
            StatUnitTypes statUnitType,
            IEnumerable<PropertyMetadataBase> properties,
            IEnumerable<Permission> permissions)
            => new QueueLogDetailsVm(item, statUnitType, properties, permissions);

        public int Id { get; }
        public DateTimeOffset? Started { get; }
        public DateTimeOffset? Ended { get; }
        public string StatId { get; }
        public string Name { get; }
        public string Unit { get; }
        public string RawUnit { get; }
        public DataUploadingLogStatuses Status { get; }
        public string Note { get; }
        public Dictionary<string, IEnumerable<string>> Errors { get; }
        public IEnumerable<string> Summary { get; }
        public StatUnitTypes StatUnitType { get; }
        public IEnumerable<PropertyMetadataBase> Properties { get; }
        public IEnumerable<Permission> Permissions { get; }
    }
}
