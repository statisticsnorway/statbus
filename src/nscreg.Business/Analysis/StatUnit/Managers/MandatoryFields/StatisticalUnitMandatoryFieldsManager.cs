using nscreg.Business.Analysis.Contracts;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data;

namespace nscreg.Business.Analysis.StatUnit.Managers.MandatoryFields
{
    /// <inheritdoc />
    /// <summary>
    /// Analysis statistical unit mandatory fields manager
    /// </summary>
    public class StatisticalUnitMandatoryFieldsManager : IMandatoryFieldsAnalysisManager
    {
        private readonly History _history;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly NSCRegDbContext _context;

        public StatisticalUnitMandatoryFieldsManager(History unit, DbMandatoryFields mandatoryFields, NSCRegDbContext context)
        {
            _history = unit;
            _mandatoryFields = mandatoryFields;
            _context = context;
        }

        /// <summary>
        /// Check mandatory fields
        /// </summary>
        /// <returns>Dictionary of messages</returns>
        public Dictionary<string, string[]> CheckFields()
        {
            var messages = new Dictionary<string, string[]>();

            if(_mandatoryFields.StatUnit.Activities && !_history.ActivitiesForLegalUnit.Any())
            {
                if (_context.ActivityLegalUnits.Any(c => c.UnitId == _history.RegId))
                {
                    messages.Add(nameof(_history.Activities), new[] { nameof(Resource.AnalysisMandatoryActivities) });
                }
            }
            if (_mandatoryFields.StatUnit.ActualAddress && _history.ActualAddress == null)
            {
                messages.Add(nameof(_history.ActualAddress), new[] { nameof(Resource.AnalysisMandatoryActualAddress) });
            }
            if (_mandatoryFields.StatUnit.Address && _history.Address == null)
            {
                messages.Add(nameof(_history.Address), new[] { nameof(Resource.AnalysisMandatoryAddress) });
            }
            if (_mandatoryFields.StatUnit.Classified && (_history.Classified == null || _history.Classified == false))
            {
                messages.Add(nameof(_history.Classified), new[] { nameof(Resource.AnalysisMandatoryClassified) });
            }
            if (_mandatoryFields.StatUnit.EmailAddress && string.IsNullOrEmpty(_history.EmailAddress))
            {
                messages.Add(nameof(_history.EmailAddress), new[] { nameof(Resource.AnalysisMandatoryEmailAddress) });
            }
            if (_mandatoryFields.StatUnit.Employees && _history.Employees == null)
            {
                messages.Add(nameof(_history.Employees), new[] { nameof(Resource.AnalysisMandatoryEmployees) });
            }
            if (_mandatoryFields.StatUnit.EmployeesDate && _history.EmployeesDate == null)
            {
                messages.Add(nameof(_history.EmployeesDate), new[] { nameof(Resource.AnalysisMandatoryEmployeesDate) });
            }
            if (_mandatoryFields.StatUnit.EmployeesYear && _history.EmployeesYear == null)
            {
                messages.Add(nameof(_history.EmployeesYear), new[] { nameof(Resource.AnalysisMandatoryEmployeesYear) });
            }
            if (_mandatoryFields.StatUnit.ExternalId && string.IsNullOrEmpty(_history.ExternalId))
            {
                messages.Add(nameof(_history.ExternalId), new[] { nameof(Resource.AnalysisMandatoryExternalId) });
            }
            if (_mandatoryFields.StatUnit.StatId && string.IsNullOrEmpty(_history.StatId))
            {
                messages.Add(nameof(_history.StatId), new[] { nameof(Resource.AnalysisMandatoryStatId) });
            }
            if (_mandatoryFields.StatUnit.StatIdDate && _history.StatIdDate == null)
            {
                messages.Add(nameof(_history.StatIdDate), new[] { nameof(Resource.AnalysisMandatoryStatIdDate )});
            }
            if (_mandatoryFields.StatUnit.RegistrationDate && _history.RegistrationDate == null)
            {
                messages.Add(nameof(_history.RegistrationDate), new[] { nameof(Resource.AnalysisMandatoryRegistrationDate) });
            }
            if (_mandatoryFields.StatUnit.TaxRegId && _history.TaxRegId == null)
            {
                messages.Add(nameof(_history.TaxRegId), new[] { nameof(Resource.AnalysisMandatoryTaxRegId) });
            }
            if (_mandatoryFields.StatUnit.TaxRegDate && _history.TaxRegDate == null)
            {
                messages.Add(nameof(_history.TaxRegDate), new[] { nameof(Resource.AnalysisMandatoryTaxRegDate) });
            }
            if (_mandatoryFields.StatUnit.Turnover && _history.Turnover == null)
            {
                messages.Add(nameof(_history.Turnover), new[] { nameof(Resource.AnalysisMandatoryTurnover) });
            }
            if (_mandatoryFields.StatUnit.TurnoverYear && _history.TurnoverYear == null)
            {
                messages.Add(nameof(_history.TurnoverYear), new[] { nameof(Resource.AnalysisMandatoryTurnoverYear) });
            }
            if (_mandatoryFields.StatUnit.TurnoverDate && _history.TurnoverDate == null)
            {
                messages.Add(nameof(_history.TurnoverDate), new[] { nameof(Resource.AnalysisMandatoryTurnoverDate) });
            }
            if (_mandatoryFields.StatUnit.StatusDate && _history.StatusDate == null)
            {
                messages.Add(nameof(_history.StatusDate), new[] { nameof(Resource.AnalysisMandatoryStatusDate) });
            }
            if (_mandatoryFields.StatUnit.ExternalIdDate && _history.ExternalIdDate == null)
            {
                messages.Add(nameof(_history.ExternalIdDate), new[] { nameof(Resource.AnalysisMandatoryExternalIdDate) });
            }
            if (_mandatoryFields.StatUnit.ExternalIdType && string.IsNullOrEmpty(_history.ExternalIdType))
            {
                messages.Add(nameof(_history.ExternalIdType), new[] { nameof(Resource.AnalysisMandatoryExternalIdType) });
            }
            if (_mandatoryFields.StatUnit.FreeEconZone && _history.FreeEconZone == false)
            {
                messages.Add(nameof(_history.FreeEconZone), new[] { nameof(Resource.AnalysisMandatoryFreeEconZone) });
            }
            if (_mandatoryFields.StatUnit.Notes && string.IsNullOrEmpty(_history.Notes))
            {
                messages.Add(nameof(_history.FreeEconZone), new[] { nameof(Resource.AnalysisMandatoryFreeEconZone) });
            }
            if (_mandatoryFields.StatUnit.NumOfPeopleEmp && _history.NumOfPeopleEmp == null)
            {
                messages.Add(nameof(_history.NumOfPeopleEmp), new[] { nameof(Resource.AnalysisMandatoryNumOfPeopleEmp) });
            }
            if (_mandatoryFields.StatUnit.Persons && !_history.PersonsForUnit.Any())
            {
                messages.Add(nameof(_history.Persons), new[] { nameof(Resource.AnalysisMandatoryPersons) });
            }
            if (_mandatoryFields.StatUnit.DataSourceClassificationId && _history.DataSourceClassificationId == null)
                messages.Add(nameof(_history.DataSourceClassificationId), new[] { nameof(Resource.AnalysisMandatoryDataSource) });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_history.Name))
                messages.Add(nameof(_history.Name), new[] { nameof(Resource.AnalysisMandatoryName) });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_history.ShortName))
                    messages.Add(nameof(_history.ShortName),
                        new[] { nameof(Resource.AnalysisMandatoryShortName) });
                else if (_history.ShortName == _history.Name)
                    messages.Add(nameof(_history.ShortName),
                        new[] { nameof(Resource.AnalysisSameNameAsShortName) });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_history.TelephoneNo))
                messages.Add(nameof(_history.TelephoneNo),
                    new[] { nameof(Resource.AnalysisMandatoryTelephoneNo) });

            if (_mandatoryFields.StatUnit.RegistrationReasonId && _history.RegistrationReasonId == null)
                messages.Add(nameof(_history.RegistrationReasonId),
                    new[] { nameof(Resource.AnalysisMandatoryRegistrationReason) });

            if (_mandatoryFields.StatUnit.SizeId && _history.SizeId == null)
            {
                messages.Add(nameof(_history.SizeId), new[] { nameof(Resource.AnalysisMandatorySize) });
            }

            if (_mandatoryFields.StatUnit.UnitStatusId && _history.UnitStatusId == null)
            {
                messages.Add(nameof(_history.UnitStatusId), new[] { nameof(Resource.AnalysisMandatoryUnitStatus) });
            }
            return messages;
        }

        public Dictionary<string, string[]> CheckOnlyIdentifiersFields()
        {
            var messages = new Dictionary<string, string[]>();
            var suStatUnitBools = new[]
            {
                _history.StatId != null,
                _history.TaxRegId != null,
                _history.ExternalId != null
            };
            if (!suStatUnitBools.Contains(true))
            {
                messages.Add(nameof(_history.RegId), new[] { Resource.AnalysisOneOfTheseFieldsShouldBeFilled });
            }
            return messages;
        }
    }
}
