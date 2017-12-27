using System;
using System.Collections.Generic;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.ModelGeneration;
using Newtonsoft.Json;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class LogItemDetailsVm
    {
        private LogItemDetailsVm(
            int id, int unitId, StatUnitTypes unitType,
            DateTime issuedAt, DateTime? resolvedAt,
            string errors, string summary,
            PropertyMetadataBase[] properties,
            IEnumerable<Permission> permisisons)
        {
            Id = id;
            UnitId = unitId;
            UnitType = unitType;
            IssuedAt = issuedAt;
            ResolvedAt = resolvedAt;
            Errors = JsonConvert.DeserializeObject<Dictionary<string, string[]>>(errors);
            Summary = summary.Split(';');
            Properties = properties;
            Permissions = permisisons;
        }

        public static LogItemDetailsVm Create(
            AnalysisLog entity,
            PropertyMetadataBase[] properties,
            IEnumerable<Permission> permisisons) =>
            new LogItemDetailsVm(
                entity.Id, entity.AnalyzedUnitId, entity.AnalyzedUnitType,
                entity.IssuedAt, entity.ResolvedAt,
                entity.ErrorValues, entity.SummaryMessages,
                properties, permisisons);

        public int Id { get; }
        public int UnitId { get; }
        public StatUnitTypes UnitType { get; }
        public DateTime IssuedAt { get; set; }
        public DateTime? ResolvedAt { get; set; }
        public Dictionary<string, string[]> Errors { get; set; }
        public IEnumerable<string> Summary { get; }
        public PropertyMetadataBase[] Properties { get; }
        public IEnumerable<Permission> Permissions { get; }
    }
}
