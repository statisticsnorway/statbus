using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    internal class StatUnitPostProcessor
    {
        private readonly Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task>> _postActionsMap;
        private readonly NSCRegDbContext _ctx;

        public StatUnitPostProcessor(NSCRegDbContext ctx)
        {
            _ctx = ctx;
            _postActionsMap = new Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, Task>>()
            {
                [DataSourceUploadTypes.Activities] = PostProcessActivitiesUpload,
                [DataSourceUploadTypes.StatUnits] = PostProcessStatUnitsUpload
            };

        }

        public async Task FillIncompleteDataOfStatUnit(StatisticalUnit unit, DataSourceUploadTypes uploadType)
        {
            await _postActionsMap[uploadType](unit);
        }

        private async Task PostProcessActivitiesUpload(StatisticalUnit unit)
        {
            if (!unit.Activities?.Any(activity => activity.Id == 0) == true)
                return;

            foreach (var activityUnit in unit.ActivitiesUnits)
            {
                if (activityUnit.Activity.Id != 0)
                    continue;
                var filled = await TryGetFilledActivityAsync(activityUnit.Activity);
                activityUnit.Activity = Mapper.Map(activityUnit.Activity, filled);
            }

            async Task<Activity> TryGetFilledActivityAsync(Activity activity)
            {
                var domainActivity = await _ctx.Activities
                    .Include(a => a.ActivityCategory)
                    .FirstOrDefaultAsync(a => a.ActivitiesUnits.Any(x => x.UnitId == unit.RegId)
                                              && a.ActivityCategory.Code == activity.ActivityCategory.Code);
                if (domainActivity != null) return domainActivity;

                activity.ActivityCategory =
                    await _ctx.ActivityCategories.FirstAsync(x => x.Code == activity.ActivityCategory.Code);
                return activity;
            }

        }

        

        private async Task PostProcessStatUnitsUpload(StatisticalUnit unit)
        {
            if (unit.Activities?.Any(activity => activity.Id == 0) == true)
                await unit.ActivitiesUnits
                    .ForEachAsync(async au =>
                    {
                        if (au.Activity.Id == 0)
                            au.Activity = await GetFilledActivity(au.Activity);
                    });

            if (unit.Address?.Id == 0)
                unit.Address = await GetFilledAddress(unit.Address);

            if (unit.ForeignParticipationCountry?.Id == 0)
                unit.ForeignParticipationCountry = await GetFilledCountry(unit.ForeignParticipationCountry);

            if (unit.LegalForm?.Id == 0)
                unit.LegalForm = await GetFilledLegalForm(unit.LegalForm);

            if (unit.Persons?.Any(person => person.Id == 0) == true)
                await unit.PersonsUnits.ForEachAsync(async pu =>
                {
                    if (pu.Person.Id == 0)
                        pu.Person = await GetFilledPerson(pu.Person);
                });

            if (unit.InstSectorCode?.Id == 0)
                unit.InstSectorCode = await GetFilledSectorCode(unit.InstSectorCode);
        }

        private async Task<Activity> GetFilledActivity(Activity parsedActivity)
        {
            return await _ctx.Activities
                       .Include(a => a.ActivityCategory)
                       .FirstOrDefaultAsync(a =>
                           a.ActivityCategory != null
                           && !a.ActivityCategory.IsDeleted
                           && (parsedActivity.ActivityType == 0 || a.ActivityType == parsedActivity.ActivityType)
                           && (parsedActivity.ActivityCategoryId == 0 ||
                               a.ActivityCategoryId == parsedActivity.ActivityCategoryId)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Code) ||
                               a.ActivityCategory.Code == parsedActivity.ActivityCategory.Code)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Name) ||
                               a.ActivityCategory.Name == parsedActivity.ActivityCategory.Name)
                           && (string.IsNullOrWhiteSpace(parsedActivity.ActivityCategory.Section) ||
                               a.ActivityCategory.Section == parsedActivity.ActivityCategory.Section))
                   ?? parsedActivity;
        }

        private async Task<Address> GetFilledAddress(Address parsedAddress)
        {
            return await _ctx.Address
                       .Include(a => a.Region)
                       .FirstOrDefaultAsync(a =>
                           a.Region != null
                           && !a.Region.IsDeleted
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart1) ||
                               a.AddressPart1 == parsedAddress.AddressPart1)
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart2) ||
                               a.AddressPart2 == parsedAddress.AddressPart2)
                           && (string.IsNullOrWhiteSpace(parsedAddress.AddressPart3) ||
                               a.AddressPart3 == parsedAddress.AddressPart3)
                           && (!parsedAddress.Latitude.HasValue ||
                               a.Latitude == parsedAddress.Latitude)
                           && (!parsedAddress.Longitude.HasValue ||
                               a.Longitude == parsedAddress.Longitude)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.Name) ||
                               a.Region.Name == parsedAddress.Region.Name)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.Code) ||
                               a.Region.Code == parsedAddress.Region.Code)
                           && (string.IsNullOrWhiteSpace(parsedAddress.Region.AdminstrativeCenter) ||
                               a.Region.AdminstrativeCenter == parsedAddress.Region.AdminstrativeCenter))
                   ?? parsedAddress;
        }

        private async Task<Country> GetFilledCountry(Country parsedCountry)
        {
            return await _ctx.Countries.FirstOrDefaultAsync(c =>
                       !c.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedCountry.Code) || c.Code == parsedCountry.Code)
                       && (string.IsNullOrWhiteSpace(parsedCountry.Name) || c.Name == parsedCountry.Name))
                   ?? parsedCountry;
        }

        private async Task<LegalForm> GetFilledLegalForm(LegalForm parsedLegalForm)
        {
            return await _ctx.LegalForms.FirstOrDefaultAsync(lf =>
                       !lf.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedLegalForm.Code) || lf.Code == parsedLegalForm.Code)
                       && (string.IsNullOrWhiteSpace(parsedLegalForm.Name) || lf.Name == parsedLegalForm.Name))
                   ?? parsedLegalForm;
        }

        private async Task<Person> GetFilledPerson(Person parsedPerson)
        {
            return await _ctx.Persons
                       .Include(p => p.NationalityCode)
                       .FirstOrDefaultAsync(p =>
                           (string.IsNullOrWhiteSpace(parsedPerson.GivenName) || p.GivenName == parsedPerson.GivenName)
                           && (string.IsNullOrWhiteSpace(parsedPerson.Surname) || p.Surname == parsedPerson.Surname)
                           && (string.IsNullOrWhiteSpace(parsedPerson.PersonalId) ||
                               p.PersonalId == parsedPerson.PersonalId)
                           && (!parsedPerson.BirthDate.HasValue || p.BirthDate == parsedPerson.BirthDate))
                   ?? parsedPerson;
        }

        private async Task<SectorCode> GetFilledSectorCode(SectorCode parsedSectorCode)
        {
            return await _ctx.SectorCodes.FirstOrDefaultAsync(sc =>
                       !sc.IsDeleted
                       && (string.IsNullOrWhiteSpace(parsedSectorCode.Code) || sc.Code == parsedSectorCode.Code)
                       && (string.IsNullOrWhiteSpace(parsedSectorCode.Name) || sc.Name == parsedSectorCode.Name))
                   ?? parsedSectorCode;
        }
    }
}
