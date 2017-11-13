using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.History;

namespace nscreg.Server.Common.Helpers
{
    public class ForeingKeysResolver
    {
        private Dictionary<string, Action<ChangedField>> foreignKeysResolver;
        private readonly NSCRegDbContext _dbContext;

        public ForeingKeysResolver( NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;

            foreignKeysResolver = new Dictionary<string, Action<ChangedField>>
            {
                [nameof(LegalUnit.HistoryLocalUnitIds)] = foreignKeyField =>
                {
                    if (!string.IsNullOrEmpty(foreignKeyField.Before))
                        foreignKeyField.Before = string.Join(", ",
                            _dbContext.LocalUnits
                                .Where(x => foreignKeyField.Before.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                    if (!string.IsNullOrEmpty(foreignKeyField.After))
                        foreignKeyField.After = string.Join(", ",
                            _dbContext.LocalUnits
                                .Where(x => foreignKeyField.After.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                },
                [nameof(EnterpriseUnit.HistoryLegalUnitIds)] = foreignKeyField =>
                {
                    if (!string.IsNullOrEmpty(foreignKeyField.Before))
                        foreignKeyField.Before = string.Join(", ",
                            _dbContext.LegalUnits
                                .Where(x => foreignKeyField.Before.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                    if (!string.IsNullOrEmpty(foreignKeyField.After))
                        foreignKeyField.After = string.Join(", ",
                            _dbContext.LegalUnits
                                .Where(x => foreignKeyField.After.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                },
                [nameof(EnterpriseGroup.HistoryEnterpriseUnitIds)] = foreignKeyField =>
                {
                    if (!string.IsNullOrEmpty(foreignKeyField.Before))
                        foreignKeyField.Before = string.Join(", ",
                            _dbContext.EnterpriseUnits
                                .Where(x => foreignKeyField.Before.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                    if (!string.IsNullOrEmpty(foreignKeyField.After))
                        foreignKeyField.After = string.Join(", ",
                            _dbContext.EnterpriseUnits
                                .Where(x => foreignKeyField.After.Split(',').Select(int.Parse).Contains(x.RegId))
                                .Select(x => x.Name)
                                .ToArray());
                },
                [nameof(LocalUnit.LegalUnitId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.LegalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = _dbContext.LegalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(LegalUnit.EnterpriseUnitRegId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.EnterpriseUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = _dbContext.EnterpriseUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(EnterpriseUnit.EntGroupId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.EnterpriseGroups
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = _dbContext.EnterpriseGroups
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(StatisticalUnit.Size)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.UnitsSize
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = _dbContext.UnitsSize
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(StatisticalUnit.ForeignParticipationId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.ForeignParticipations
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = _dbContext.ForeignParticipations
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(StatisticalUnit.DataSourceClassificationId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.DataSourceClassifications
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = _dbContext.DataSourceClassifications
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(StatisticalUnit.ReorgTypeId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.ReorgTypes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = _dbContext.ReorgTypes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(StatisticalUnit.UnitStatusId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.UnitStatuses
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = _dbContext.UnitStatuses
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(StatisticalUnit.ParentOrgLink)] = foreignKeyField =>
                {
                    foreignKeyField.Before = _dbContext.StatisticalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = _dbContext.StatisticalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
            };
        }

        public Action<ChangedField> this[string index] => foreignKeysResolver[index];

        public Dictionary<string, Action<ChangedField>>.KeyCollection Keys => foreignKeysResolver.Keys;
    }
}
