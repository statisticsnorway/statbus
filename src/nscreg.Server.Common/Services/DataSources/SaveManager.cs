using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class SaveManager
    {
        //private CreateUnitService _createSvc;

        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, Task>> _createByType;

        private readonly ElasticService _elasticService;

        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, Task>> _updateByType;

        //private readonly NSCRegDbContext _ctx;

        //private readonly UserService _usrService;

        private  SaveManager(NSCRegDbContext context, string userId)
        {
           // _ctx = context;
            //_usrService = new UserService(context);
            _elasticService = new ElasticService(context);
            var createUnitService = new CreateUnitService(context, userId, _elasticService);
            _createByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit) =>
                    createUnitService.CreateLegalUnit(unit as LegalUnit),
                [StatUnitTypes.LocalUnit] = (unit) =>
                    createUnitService.CreateLocalUnit(unit as LocalUnit),
                [StatUnitTypes.EnterpriseUnit] = (unit) =>
                    createUnitService.CreateEnterpriseUnit(unit as EnterpriseUnit)
            };
            //_updateByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>>
            //{
            //    [StatUnitTypes.LegalUnit] = (unit, userId) =>
            //        editSvc.EditLegalUnit(MappedUnitM(unit, StatUnitTypes.LegalUnit, "LegalUnitEditM", userId), userId),
            //    [StatUnitTypes.LocalUnit] = (unit, userId) =>
            //        editSvc.EditLocalUnit(MappedUnitM(unit, StatUnitTypes.LocalUnit, "LocalUnitEditM", userId), userId),
            //    [StatUnitTypes.EnterpriseUnit] = (unit, userId) =>
            //        editSvc.EditEnterpriseUnit(MappedUnitM(unit, StatUnitTypes.EnterpriseUnit, "EnterpriseUnitEditM", userId), userId)
            //};
        }

        public static async Task<SaveManager> CreateSaveManager(NSCRegDbContext context, string userId)
        {
            var saveManager = new SaveManager(context, userId);
            await saveManager._elasticService.CheckElasticSearchConnection();
            return saveManager;
        }

        private async Task<(string, bool)> SaveStatUnitsUpload(StatisticalUnit parsedUnit, DataSource dataSource,
            string userId, bool isNeW)
        {
            // TODO: вероятно, лишний запрос. Такое делается до Analyze (Populate возвращает isNew)
            if (dataSource.Priority != DataSourcePriority.Trusted &&
                (dataSource.Priority != DataSourcePriority.Ok || isNeW))
                return (null, false);

            var saveAction =
                isNeW && ( dataSource.AllowedOperations == DataSourceAllowedOperation.Alter || dataSource.AllowedOperations == DataSourceAllowedOperation.CreateAndAlter) ? _updateByType[dataSource.StatUnitType] : _createByType[dataSource.StatUnitType];

            try
            {
                await saveAction(parsedUnit);
            }
            catch (Exception ex)
            {
                return (GetFullExceptionMessage(ex), false);
            }
            return (null, true);
        }

        private string GetFullExceptionMessage(Exception ex)
        {
#if DEBUG
            return ex + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
#else
            return ex.Message + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
#endif
        }


        public async Task<(string, bool)> SaveUnit(StatisticalUnit parsedUnit, DataSource dataSource, string userId, bool isNew)
        {
            return await SaveStatUnitsUpload(parsedUnit, dataSource, userId, isNew);
        }

        //private dynamic MappedUnitM(StatisticalUnit unit, StatUnitTypes type, string mapperType, string userId)
        //{
        //    var dataAccess = _usrService.GetDataAccessAttributes(userId, type);
        //    var mappedActivities = new List<ActivityM>();
        //    var mappedPersons = new List<PersonM>();
        //    var mappedForeignParticipationCountriesUnits = new List<int>();
        //    var mappedUnit = new StatUnitModelBase();

        //    if (type == StatUnitTypes.LocalUnit && mapperType == "LocalUnitCreateM")
        //        mappedUnit = Mapper.Map<LocalUnitCreateM>(unit);
        //    else if (type == StatUnitTypes.LegalUnit && mapperType == "LegalUnitCreateM")
        //        mappedUnit = Mapper.Map<LegalUnitCreateM>(unit);
        //    else if (type == StatUnitTypes.EnterpriseUnit && mapperType == "EnterpriseUnitCreateM")
        //        mappedUnit = Mapper.Map<EnterpriseUnitCreateM>(unit);
        //    else if (type == StatUnitTypes.LocalUnit && mapperType == "LocalUnitEditM")
        //        mappedUnit = Mapper.Map<LocalUnitEditM>(unit);
        //    else if (type == StatUnitTypes.LegalUnit && mapperType == "LegalUnitEditM")
        //        mappedUnit = Mapper.Map<LegalUnitEditM>(unit);
        //    else if (type == StatUnitTypes.EnterpriseUnit && mapperType == "EnterpriseUnitEditM")
        //        mappedUnit = Mapper.Map<EnterpriseUnitEditM>(unit);


        //    mappedUnit.DataAccess = dataAccess.Result;
        //    mappedUnit.Address = Mapper.Map<AddressM>(unit.Address);
        //    mappedUnit.ActualAddress = Mapper.Map<AddressM>(unit.ActualAddress);
        //    mappedUnit.PostalAddress = Mapper.Map<AddressM>(unit.PostalAddress);

        //    unit.Activities.ForEach(activity => mappedActivities.Add(Mapper.Map<ActivityM>(activity)));
        //    foreach (var personStatisticalUnit in unit.PersonsUnits)
        //    {
        //        var person = Mapper.Map<PersonM>(personStatisticalUnit.Person);
        //        if (personStatisticalUnit.PersonTypeId != null)
        //        {
        //            person.Role = (int) personStatisticalUnit.PersonTypeId;
        //        }
        //        mappedPersons.Add(person);
        //    }
        //    unit.ForeignParticipationCountriesUnits.ForEach(fpcu => mappedForeignParticipationCountriesUnits.Add(fpcu.Id));
        //    mappedUnit.ForeignParticipationCountriesUnits = mappedForeignParticipationCountriesUnits;
        //    mappedUnit.ForeignParticipationId = unit.ForeignParticipation?.Id;
        //    mappedUnit.Activities = mappedActivities;
        //    mappedUnit.Persons = mappedPersons;

        //    return mappedUnit;
        //}

    }
}
