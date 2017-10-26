using System.Collections.Generic;
using System.Linq;
using nscreg.Business.Analysis.StatUnit.Rules;
using nscreg.Data.Entities;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Business.Analysis.StatUnit.Analyzers
{
    /// <inheritdoc />
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public abstract class BaseAnalyzer : IStatUnitAnalyzer
    {
        protected readonly StatUnitAnalysisRules _analysisRules;
        protected readonly DbMandatoryFields _mandatoryFields;

        protected BaseAnalyzer(StatUnitAnalysisRules analysisRules, DbMandatoryFields mandatoryFields)
        {
            _analysisRules = analysisRules;
            _mandatoryFields = mandatoryFields;
        }
        
        public virtual Dictionary<string, string[]> CheckConnections(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new ConnectionsManager(unit);
            (string key, string[] value) tuple;
            
            if (_analysisRules.Connections.CheckRelatedLegalUnit)
                if (!isAnyRelatedLegalUnit)
                    messages.Add(unit is LocalUnit ? nameof(LocalUnit.LegalUnitId) : nameof(EnterpriseUnit.LegalUnits),
                        new[] {"Stat unit doesn't have related legal unit"});

            if(_analysisRules.Connections.CheckRelatedActivities)
                if (!isAnyRelatedActivities)
                    messages.Add(nameof(StatisticalUnit.Activities), new[] { "Stat unit doesn't have related activity" });

            if (_analysisRules.Connections.CheckAddress)
            {
                tuple = manager.CheckAddress(addresses);
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }
       
        public virtual Dictionary<string, string[]> CheckMandatoryFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();
            var manager = new MandatoryFieldsManager(unit);
            (string key, string[] value) tuple;
            
            if (_mandatoryFields.StatUnit.DataSource)
            {
                tuple = manager.CheckDataSource();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.Name)
            {
                tuple = manager.CheckName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.ShortName)
            {
                tuple = manager.CheckShortName();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.TelephoneNo)
            {
                tuple = manager.CheckTelephoneNo();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.RegistrationReason)
            {
                tuple = manager.CheckRegistrationReason();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.ContactPerson)
            {
                tuple = manager.CheckContactPerson();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.StatUnit.Status)
            {
                tuple = manager.CheckStatus();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }
            if (_mandatoryFields.LegalUnit.Owner)
            {
                tuple = manager.CheckLegalUnitOwner();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }
     
        public virtual Dictionary<string, string[]> CheckCalculationFields(IStatisticalUnit unit)
        {
            var manager = new CalculationFieldsManager(unit);
            var messages = new Dictionary<string, string[]>();
            (string key, string[] value) tuple;

            if (_analysisRules.CalculationFields.StatId)
            {
                tuple = manager.CheckOkpo();
                if (tuple.key != null)
                    messages.Add(tuple.key, tuple.value);
            }

            return messages;
        }

        public abstract Dictionary<string, string[]> CheckDuplicates(IStatisticalUnit unit, List<IStatisticalUnit> units);

        public virtual AnalysisResult CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses, List<IStatisticalUnit> units)
        {
            var messages = new Dictionary<string, string[]>();
            var summaryMessages = new List<string>();

            var connectionsResult = CheckConnections(unit, isAnyRelatedLegalUnit, isAnyRelatedActivities, addresses);
            if (connectionsResult.Any())
            {
                summaryMessages.Add("Connection rules warnings");
                messages.AddRange(connectionsResult);
            }

            var mandatoryFieldsResult = CheckMandatoryFields(unit);
            if (mandatoryFieldsResult.Any())
            {
                summaryMessages.Add("Mandatory fields rules warnings");
                messages.AddRange(mandatoryFieldsResult);
            }

            var calculationFieldsResult = CheckCalculationFields(unit);
            if (calculationFieldsResult.Any())
            {
                summaryMessages.Add("Calculation fields rules warnings");
                calculationFieldsResult.ForEach(d =>
                {
                    if (messages.ContainsKey(d.Key))
                    {
                        var existed = messages[d.Key];
                        messages[d.Key] = existed.Concat(d.Value).ToArray();
                    }
                    else
                        messages.Add(d.Key, d.Value);
                });
            }

            if (units.Any())
            {
                var duplicatesResult = CheckDuplicates(unit, units);
                if (duplicatesResult.Any())
                {
                    summaryMessages.Add("Duplicate fields rules warnings");

                    duplicatesResult.ForEach(d =>
                    {
                        if (messages.ContainsKey(d.Key))
                        {
                            var existed = messages[d.Key];
                            messages[d.Key] = existed.Concat(d.Value).ToArray();
                        }
                        else
                            messages.Add(d.Key, d.Value);
                    });
                }
            }
            

            return new AnalysisResult
            {
                Name = unit.Name,
                Type = unit.UnitType,
                Messages = messages,
                SummaryMessages = summaryMessages
            };
        }
    }
}
