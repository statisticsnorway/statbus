using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Helpers
{
    public partial class StatUnitCreationHelper
    {
        private async Task<T> CreateStatUnitAsync<T>(T entity) where T : class
        {
            return (await _dbContext.Set<T>().AddAsync(entity)).Entity;            
        }
        
        private async Task<LocalUnit> CreateLocalForLegalAsync(LegalUnit legalUnit)
        {
            var localUnit = new LocalUnit
            {
                Address = legalUnit.Address,
                ActualAddress = legalUnit.ActualAddress,
                LegalUnit = legalUnit
            };

            _mapper.Map(legalUnit, localUnit);
            await _dbContext.LocalUnits.AddAsync(localUnit);
         
            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits, legalUnit.ForeignParticipationCountriesUnits, localUnit);

            return localUnit;
        }

        private async Task<EnterpriseUnit> CreateEnterpriseForLegalAsync(LegalUnit legalUnit)
        {
            var enterpriseUnit = new EnterpriseUnit
            {
                Address = legalUnit.Address,
                ActualAddress = legalUnit.ActualAddress,
            };
            _mapper.Map(legalUnit, enterpriseUnit);
            await _dbContext.EnterpriseUnits.AddAsync(enterpriseUnit);
            legalUnit.EnterpriseUnit = enterpriseUnit;

            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits, legalUnit.ForeignParticipationCountriesUnits, enterpriseUnit);

            return enterpriseUnit;
        }

        private async Task<EnterpriseGroup> CreateGroupForEnterpriseAsync(EnterpriseUnit enterpriseUnit)
        {
            var enterpriseGroup = new EnterpriseGroup
            {
                Address = enterpriseUnit.Address,
                ActualAddress = enterpriseUnit.ActualAddress,
            };

            _mapper.Map(enterpriseUnit, enterpriseGroup);
            enterpriseUnit.EnterpriseGroup = enterpriseGroup;
            await _dbContext.EnterpriseGroups.AddAsync(enterpriseGroup);

            return enterpriseGroup;
        }

        private void CreateActivitiesAndPersonsAndForeignParticipations(IEnumerable<Activity> activities, IEnumerable<PersonStatisticalUnit> persons, IEnumerable<CountryStatisticalUnit> foreignPartCountries, StatisticalUnit unit)
        {
            activities.ForEach(activiti =>
            {
                _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                {
                    ActivityId = activiti.Id,
                    Unit = unit
                });
            });

            persons.ForEach(person =>
            {
                _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                {
                    PersonId = person.PersonId,
                    Unit = unit,
                    PersonTypeId = person.PersonTypeId,
                    EnterpriseGroupId = person.EnterpriseGroupId
                });
            });

            foreignPartCountries.ForEach(country =>
            {
                _dbContext.CountryStatisticalUnits.Add(new CountryStatisticalUnit
                {
                    Unit = unit,
                    CountryId = country.CountryId
                });
            });
        }
    }
}
