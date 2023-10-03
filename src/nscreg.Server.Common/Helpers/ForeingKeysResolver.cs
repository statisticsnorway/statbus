using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.History;

namespace nscreg.Server.Common.Helpers
{
    public class ForeingKeysResolver
    {
        private Dictionary<string, Action<ChangedField>> foreignKeysResolver;

        public ForeingKeysResolver(NSCRegDbContext dbContext)
        {

            foreignKeysResolver = new Dictionary<string, Action<ChangedField>>
            {
                [nameof(LocalUnit.LegalUnitId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.LegalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = dbContext.LegalUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(LegalUnit.EnterpriseUnitRegId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.EnterpriseUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = dbContext.EnterpriseUnits
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(EnterpriseUnit.EnterpriseGroupId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.EnterpriseGroups
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.RegId)?.Name;
                    foreignKeyField.After = dbContext.EnterpriseGroups
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.RegId)?.Name;
                },
                [nameof(History.SizeId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.UnitSizes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = dbContext.UnitSizes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(History.DataSourceClassificationId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.DataSourceClassifications
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = dbContext.DataSourceClassifications
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(History.ReorgTypeId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.ReorgTypes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = dbContext.ReorgTypes
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(History.UnitStatusId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.UnitStatuses
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = dbContext.UnitStatuses
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
                [nameof(History.LegalFormId)] = foreignKeyField =>
                {
                    foreignKeyField.Before = dbContext.LegalForms
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.Before) && int.Parse(foreignKeyField.Before) == x.Id)?.Name;
                    foreignKeyField.After = dbContext.LegalForms
                        .FirstOrDefault(x => !string.IsNullOrEmpty(foreignKeyField.After) && int.Parse(foreignKeyField.After) == x.Id)?.Name;
                },
            };
        }

        public Action<ChangedField> this[string index] => foreignKeysResolver[index];

        public Dictionary<string, Action<ChangedField>>.KeyCollection Keys => foreignKeysResolver.Keys;
    }
}
