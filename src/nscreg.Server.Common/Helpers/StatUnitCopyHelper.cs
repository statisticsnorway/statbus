using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Helpers
{
    public partial class StatUnitCreationHelper
    {
        private async Task<T> CreateStatUnitAsync<T>(T entity) where T : class
        {
            var result = _dbContext.Set<T>().Add(entity).Entity;
            try
            {
                await _dbContext.SaveChangesAsync();
                return result;
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private void CreateActivitiesAndPersons(IEnumerable<Activity> activities, IEnumerable<Person> persons, int statUnitId)
        {
            activities.ForEach(x =>
            {
                _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                {
                    ActivityId = x.Id,
                    UnitId = statUnitId
                });
            });
            persons.ForEach(x =>
            {
                _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                {
                    PersonId = x.Id,
                    UnitId = statUnitId,
                    PersonType = x.Role
                });
            });
        }

        private async Task CreateLocalForLegalAsync(LegalUnit legalUnit)
        {
            var localUnit = new LocalUnit
            {
                AddressId = legalUnit.AddressId,
                ActualAddressId = legalUnit.ActualAddressId,
                LegalUnitId = legalUnit.RegId
            };

            Mapper.Map(legalUnit, localUnit);
            _dbContext.LocalUnits.Add(localUnit);
            await _dbContext.SaveChangesAsync();

            legalUnit.HistoryLocalUnitIds = localUnit.RegId.ToString();
            _dbContext.LegalUnits.Update(legalUnit);
            await _dbContext.SaveChangesAsync();

            CreateActivitiesAndPersons(legalUnit.Activities, legalUnit.Persons, localUnit.RegId);
            await _dbContext.SaveChangesAsync();
        }

        private async Task CreateEnterpriseForLegalAsync(LegalUnit legalUnit)
        {
            var enterpriseUnit = new EnterpriseUnit
            {
                AddressId = legalUnit.AddressId,
                ActualAddressId = legalUnit.ActualAddressId,
                HistoryLegalUnitIds = legalUnit.RegId.ToString()
            };
            Mapper.Map(legalUnit, enterpriseUnit);
            _dbContext.EnterpriseUnits.Add(enterpriseUnit);
            await _dbContext.SaveChangesAsync();

            legalUnit.EnterpriseUnitRegId = enterpriseUnit.RegId;
            _dbContext.LegalUnits.Update(legalUnit);
            await _dbContext.SaveChangesAsync();

            CreateActivitiesAndPersons(legalUnit.Activities, legalUnit.Persons, enterpriseUnit.RegId);
            await _dbContext.SaveChangesAsync();
        }
    }
}
