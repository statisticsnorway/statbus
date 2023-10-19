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
        private readonly StatisticalUnit _statisticalUnit;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly NSCRegDbContext _context;

        public StatisticalUnitMandatoryFieldsManager(StatisticalUnit unit, DbMandatoryFields mandatoryFields, NSCRegDbContext context)
        {
            _statisticalUnit = unit;
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

            if(_mandatoryFields.StatUnit.Activities && !_statisticalUnit.ActivitiesUnits.Any())
            {
                if (_context.ActivityStatisticalUnits.Any(c => c.UnitId == _statisticalUnit.RegId))
                {
                    messages.Add(nameof(_statisticalUnit.Activities), new[] { nameof(Resource.AnalysisMandatoryActivities) });
                }
            }
            if (_mandatoryFields.StatUnit.ActualAddress && _statisticalUnit.ActualAddress == null)
            {
                messages.Add(nameof(_statisticalUnit.ActualAddress), new[] { nameof(Resource.AnalysisMandatoryActualAddress) });
            }
            if (_mandatoryFields.StatUnit.Classified && (_statisticalUnit.Classified == null || _statisticalUnit.Classified == false))
            {
                messages.Add(nameof(_statisticalUnit.Classified), new[] { nameof(Resource.AnalysisMandatoryClassified) });
            }
            if (_mandatoryFields.StatUnit.EmailAddress && string.IsNullOrEmpty(_statisticalUnit.EmailAddress))
            {
                messages.Add(nameof(_statisticalUnit.EmailAddress), new[] { nameof(Resource.AnalysisMandatoryEmailAddress) });
            }
            if (_mandatoryFields.StatUnit.Employees && _statisticalUnit.Employees == null)
            {
                messages.Add(nameof(_statisticalUnit.Employees), new[] { nameof(Resource.AnalysisMandatoryEmployees) });
            }
            if (_mandatoryFields.StatUnit.EmployeesDate && _statisticalUnit.EmployeesDate == null)
            {
                messages.Add(nameof(_statisticalUnit.EmployeesDate), new[] { nameof(Resource.AnalysisMandatoryEmployeesDate) });
            }
            if (_mandatoryFields.StatUnit.EmployeesYear && _statisticalUnit.EmployeesYear == null)
            {
                messages.Add(nameof(_statisticalUnit.EmployeesYear), new[] { nameof(Resource.AnalysisMandatoryEmployeesYear) });
            }
            if (_mandatoryFields.StatUnit.ExternalId && string.IsNullOrEmpty(_statisticalUnit.ExternalId))
            {
                messages.Add(nameof(_statisticalUnit.ExternalId), new[] { nameof(Resource.AnalysisMandatoryExternalId) });
            }
            if (_mandatoryFields.StatUnit.StatId && string.IsNullOrEmpty(_statisticalUnit.StatId))
            {
                messages.Add(nameof(_statisticalUnit.StatId), new[] { nameof(Resource.AnalysisMandatoryStatId) });
            }
            if (_mandatoryFields.StatUnit.StatIdDate && _statisticalUnit.StatIdDate == null)
            {
                messages.Add(nameof(_statisticalUnit.StatIdDate), new[] { nameof(Resource.AnalysisMandatoryStatIdDate )});
            }
            if (_mandatoryFields.StatUnit.RegistrationDate && _statisticalUnit.RegistrationDate == null)
            {
                messages.Add(nameof(_statisticalUnit.RegistrationDate), new[] { nameof(Resource.AnalysisMandatoryRegistrationDate) });
            }
            if (_mandatoryFields.StatUnit.TaxRegId && _statisticalUnit.TaxRegId == null)
            {
                messages.Add(nameof(_statisticalUnit.TaxRegId), new[] { nameof(Resource.AnalysisMandatoryTaxRegId) });
            }
            if (_mandatoryFields.StatUnit.TaxRegDate && _statisticalUnit.TaxRegDate == null)
            {
                messages.Add(nameof(_statisticalUnit.TaxRegDate), new[] { nameof(Resource.AnalysisMandatoryTaxRegDate) });
            }
            if (_mandatoryFields.StatUnit.Turnover && _statisticalUnit.Turnover == null)
            {
                messages.Add(nameof(_statisticalUnit.Turnover), new[] { nameof(Resource.AnalysisMandatoryTurnover) });
            }
            if (_mandatoryFields.StatUnit.TurnoverYear && _statisticalUnit.TurnoverYear == null)
            {
                messages.Add(nameof(_statisticalUnit.TurnoverYear), new[] { nameof(Resource.AnalysisMandatoryTurnoverYear) });
            }
            if (_mandatoryFields.StatUnit.TurnoverDate && _statisticalUnit.TurnoverDate == null)
            {
                messages.Add(nameof(_statisticalUnit.TurnoverDate), new[] { nameof(Resource.AnalysisMandatoryTurnoverDate) });
            }
            if (_mandatoryFields.StatUnit.StatusDate && _statisticalUnit.StatusDate == null)
            {
                messages.Add(nameof(_statisticalUnit.StatusDate), new[] { nameof(Resource.AnalysisMandatoryStatusDate) });
            }
            if (_mandatoryFields.StatUnit.ExternalIdDate && _statisticalUnit.ExternalIdDate == null)
            {
                messages.Add(nameof(_statisticalUnit.ExternalIdDate), new[] { nameof(Resource.AnalysisMandatoryExternalIdDate) });
            }
            if (_mandatoryFields.StatUnit.ExternalIdType && string.IsNullOrEmpty(_statisticalUnit.ExternalIdType))
            {
                messages.Add(nameof(_statisticalUnit.ExternalIdType), new[] { nameof(Resource.AnalysisMandatoryExternalIdType) });
            }
            if (_mandatoryFields.StatUnit.FreeEconZone && _statisticalUnit.FreeEconZone == false)
            {
                messages.Add(nameof(_statisticalUnit.FreeEconZone), new[] { nameof(Resource.AnalysisMandatoryFreeEconZone) });
            }
            if (_mandatoryFields.StatUnit.Notes && string.IsNullOrEmpty(_statisticalUnit.Notes))
            {
                messages.Add(nameof(_statisticalUnit.FreeEconZone), new[] { nameof(Resource.AnalysisMandatoryFreeEconZone) });
            }
            if (_mandatoryFields.StatUnit.NumOfPeopleEmp && _statisticalUnit.NumOfPeopleEmp == null)
            {
                messages.Add(nameof(_statisticalUnit.NumOfPeopleEmp), new[] { nameof(Resource.AnalysisMandatoryNumOfPeopleEmp) });
            }
            if (_mandatoryFields.StatUnit.Persons && !_statisticalUnit.PersonsUnits.Any())
            {
                messages.Add(nameof(_statisticalUnit.Persons), new[] { nameof(Resource.AnalysisMandatoryPersons) });
            }
            if (_mandatoryFields.StatUnit.DataSourceClassificationId && _statisticalUnit.DataSourceClassificationId == null)
                messages.Add(nameof(_statisticalUnit.DataSourceClassificationId), new[] { nameof(Resource.AnalysisMandatoryDataSource) });

            if (_mandatoryFields.StatUnit.Name && string.IsNullOrEmpty(_statisticalUnit.Name))
                messages.Add(nameof(_statisticalUnit.Name), new[] { nameof(Resource.AnalysisMandatoryName) });

            if (_mandatoryFields.StatUnit.ShortName)
            {
                if (string.IsNullOrEmpty(_statisticalUnit.ShortName))
                    messages.Add(nameof(_statisticalUnit.ShortName),
                        new[] { nameof(Resource.AnalysisMandatoryShortName) });
                else if (_statisticalUnit.ShortName == _statisticalUnit.Name)
                    messages.Add(nameof(_statisticalUnit.ShortName),
                        new[] { nameof(Resource.AnalysisSameNameAsShortName) });
            }

            if (_mandatoryFields.StatUnit.TelephoneNo && string.IsNullOrEmpty(_statisticalUnit.TelephoneNo))
                messages.Add(nameof(_statisticalUnit.TelephoneNo),
                    new[] { nameof(Resource.AnalysisMandatoryTelephoneNo) });

            if (_mandatoryFields.StatUnit.RegistrationReasonId && _statisticalUnit.RegistrationReasonId == null)
                messages.Add(nameof(_statisticalUnit.RegistrationReasonId),
                    new[] { nameof(Resource.AnalysisMandatoryRegistrationReason) });

            if (_mandatoryFields.StatUnit.SizeId && _statisticalUnit.SizeId == null)
            {
                messages.Add(nameof(_statisticalUnit.SizeId), new[] { nameof(Resource.AnalysisMandatorySize) });
            }

            if (_mandatoryFields.StatUnit.UnitStatusId && _statisticalUnit.UnitStatusId == null)
            {
                messages.Add(nameof(_statisticalUnit.UnitStatusId), new[] { nameof(Resource.AnalysisMandatoryUnitStatus) });
            }
            return messages;
        }

        public Dictionary<string, string[]> CheckOnlyIdentifiersFields()
        {
            var messages = new Dictionary<string, string[]>();
            var suStatUnitBools = new[]
            {
                _statisticalUnit.StatId != null,
                _statisticalUnit.TaxRegId != null,
                _statisticalUnit.ExternalId != null
            };
            if (!suStatUnitBools.Contains(true))
            {
                messages.Add(nameof(_statisticalUnit.RegId), new[] { Resource.AnalysisOneOfTheseFieldsShouldBeFilled });
            }
            return messages;
        }
    }
}
