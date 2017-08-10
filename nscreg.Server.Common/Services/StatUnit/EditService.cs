using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Services.Analysis.StatUnit;
using nscreg.Server.Common.Validators.Extentions;

using nscreg.Utilities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class EditService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;
        private readonly Common _commonSvc;

        public EditService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);
        }

        public async Task<Dictionary<string, string[]>> EditLegalUnit(LegalUnitEditM data, string userId)
            => await EditUnitContext<LegalUnit, LegalUnitEditM>(
                data,
                m => m.RegId.Value,
                userId,
                unit =>
                {
                    if (Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                    {
                        var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                        unit.LocalUnits.Clear();
                        foreach (var localUnit in localUnits)
                        {
                            unit.LocalUnits.Add(localUnit);
                        }
                    }
                    return Task.CompletedTask;
                });

        public async Task<Dictionary<string, string[]>> EditLocalUnit(LocalUnitEditM data, string userId)
            => await EditUnitContext<LocalUnit, LocalUnitEditM>(
                data,
                v => v.RegId.Value,
                userId,
                null);

        public async Task<Dictionary<string, string[]>> EditEnterpriseUnit(EnterpriseUnitEditM data, string userId)
            => await EditUnitContext<EnterpriseUnit, EnterpriseUnitEditM>(
                data,
                m => m.RegId.Value,
                userId,
                unit =>
                {
                    if (Common.HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LocalUnits))
                    {
                        var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                        unit.LocalUnits.Clear();
                        foreach (var localUnit in localUnits)
                        {
                            unit.LocalUnits.Add(localUnit);
                        }
                    }
                    if (Common.HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LegalUnits))
                    {
                        var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
                        unit.LegalUnits.Clear();
                        foreach (var legalUnit in legalUnits)
                        {
                            unit.LegalUnits.Add(legalUnit);
                        }
                    }
                    return Task.CompletedTask;
                });

        public async Task<Dictionary<string, string[]>> EditEnterpriseGroup(EnterpriseGroupEditM data, string userId)
            => await EditContext<EnterpriseGroup, EnterpriseGroupEditM>(
                data,
                m => m.RegId.Value,
                userId,
                unit =>
                {
                    if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                    {
                        var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
                        unit.EnterpriseUnits.Clear();
                        foreach (var enterprise in enterprises)
                        {
                            unit.EnterpriseUnits.Add(enterprise);
                        }
                    }
                    if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.LegalUnits))
                    {
                        unit.LegalUnits.Clear();
                        var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                        foreach (var legalUnit in legalUnits)
                        {
                            unit.LegalUnits.Add(legalUnit);
                        }
                    }
                    return Task.CompletedTask;
                });

        private async Task<Dictionary<string, string[]>> EditUnitContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work)
            where TModel : StatUnitModelBase
            where TUnit : StatisticalUnit, new()
            => await EditContext<TUnit, TModel>(
                data,
                idSelector,
                userId,
                async unit =>
                {
                    //Merge activities
                    if (Common.HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                    {
                        var activities = new List<ActivityStatisticalUnit>();
                        var srcActivities = unit.ActivitiesUnits.ToDictionary(v => v.ActivityId);
                        var activitiesList = data.Activities ?? new List<ActivityM>();

                        //Get Ids for codes
                        var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
                        var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

                        var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                            nameof(Resource.ActivityCategoryLookup),
                            await activityService.List(false, v => codesList.Contains(v.Code))
                        );

                        foreach (var model in activitiesList)
                        {
                            ActivityStatisticalUnit activityAndUnit;

                            if (model.Id.HasValue && srcActivities.TryGetValue(model.Id.Value, out activityAndUnit))
                            {
                                var currentActivity = activityAndUnit.Activity;
                                if (model.ActivityRevxCategory.Id == currentActivity.ActivityRevx &&
                                    ObjectComparer.SequentialEquals(model, currentActivity))
                                {
                                    activities.Add(activityAndUnit);
                                    continue;
                                }
                            }
                            var newActivity = new Activity();
                            Mapper.Map(model, newActivity);
                            newActivity.UpdatedBy = userId;
                            newActivity.ActivityRevx = codesLookup.Get(model.ActivityRevxCategory.Code).Id;
                            activities.Add(new ActivityStatisticalUnit() {Activity = newActivity});
                        }
                        var activitiesUnits = unit.ActivitiesUnits;
                        activitiesUnits.Clear();
                        unit.ActivitiesUnits.AddRange(activities);
                    }

                var persons = new List<PersonStatisticalUnit>();
                var srcPersons = unit.PersonsUnits.ToDictionary(v => v.PersonId);
                var personsList = data.Persons ?? new List<PersonM>();

                foreach (var model in personsList)
                {
                    PersonStatisticalUnit personStatisticalUnit;

                    if (model.Id.HasValue && srcPersons.TryGetValue(model.Id.Value, out personStatisticalUnit))
                    {
                        var currentPerson = personStatisticalUnit.Person;
                        if (model.Id == currentPerson.Id)
                        {
                            currentPerson.UpdateProperties(model);
                            persons.Add(personStatisticalUnit);
                            continue;
                        }
                    }
                    var newPerson = new Person();
                    Mapper.Map(model, newPerson);
                    persons.Add(new PersonStatisticalUnit {Person = newPerson, PersonType = newPerson.Role});
                }
                var personsUnits = unit.PersonsUnits;
                personsUnits.Clear();
                unit.PersonsUnits.AddRange(persons);

                    if (work != null)
                    {
                        await work(unit);
                    }
                });

        private async Task<Dictionary<string, string[]>> EditContext<TUnit, TModel>(
            TModel data,
            Func<TModel, int> idSelector,
            string userId,
            Func<TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = (TUnit) await ValidateChanges<TUnit>(data, idSelector(data));
            await _commonSvc.InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);

            var unitsHistoryHolder = new UnitsHistoryHolder(unit);

            var hUnit = new TUnit();
            Mapper.Map(unit, hUnit);
            Mapper.Map(data, unit);

            //External Mappings
            if (work != null)
            {
                await work(unit);
            }


           
            _commonSvc.AddAddresses<TUnit>(unit, data);
            if (IsNoChanges(unit, hUnit)) return null;

            unit.UserId = userId;
            unit.ChangeReason = data.ChangeReason;
            unit.EditComment = data.EditComment;

            //var analyzer = new StatUnitAnalyzer(
            //    new Dictionary<StatUnitMandatoryFieldsEnum, bool>
            //    {
            //        { StatUnitMandatoryFieldsEnum.CheckAddress, true },
            //        { StatUnitMandatoryFieldsEnum.CheckContactPerson, true },
            //        { StatUnitMandatoryFieldsEnum.CheckDataSource, true },
            //        { StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner, true },
            //        { StatUnitMandatoryFieldsEnum.CheckName, true },
            //        { StatUnitMandatoryFieldsEnum.CheckRegistrationReason, true },
            //        { StatUnitMandatoryFieldsEnum.CheckShortName, true },
            //        { StatUnitMandatoryFieldsEnum.CheckStatus, true },
            //        { StatUnitMandatoryFieldsEnum.CheckTelephoneNo, true },
            //    },
            //    new Dictionary<StatUnitConnectionsEnum, bool>
            //    {
            //        {StatUnitConnectionsEnum.CheckRelatedActivities, true},
            //        {StatUnitConnectionsEnum.CheckRelatedLegalUnit, true},
            //        {StatUnitConnectionsEnum.CheckAddress, true},
            //    },
            //    new Dictionary<StatUnitOrphanEnum, bool>
            //    {
            //        {StatUnitOrphanEnum.CheckRelatedEnterpriseGroup, true},
            //    });

            //IStatUnitAnalyzeService analysisService = new StatUnitAnalyzeService(_dbContext, analyzer);
            //var analyzeResult = analysisService.AnalyzeStatUnit(unit);
            //if (analyzeResult.Messages.Any()) return analyzeResult.Messages;

            _dbContext.Set<TUnit>().Add((TUnit) Common.TrackHistory(unit, hUnit));


            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var changeDateTime = DateTime.Now;
                    _dbContext.Set<TUnit>().Add((TUnit)Common.TrackHistory(unit, hUnit, changeDateTime));
                    await _dbContext.SaveChangesAsync();

                    _commonSvc.TrackRelatedUnitsHistory(unit, hUnit, userId, data.ChangeReason, data.EditComment, changeDateTime, unitsHistoryHolder);
                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    //TODO: Processing Validation Errors
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            return null;
        }

        private async Task<IStatisticalUnit> ValidateChanges<T>(IStatUnitM data, int regid)
            where T : class, IStatisticalUnit
        {
            var unit = await _commonSvc.GetStatisticalUnitByIdAndType(
                regid,
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(T)),
                false);

            if (!unit.Name.Equals(data.Name) &&
                !_commonSvc.NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            if (data.Address != null && data.ActualAddress != null && !data.Address.Equals(unit.Address) &&
                !data.ActualAddress.Equals(unit.ActualAddress) &&
                !_commonSvc.NameAddressIsUnique<T>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            if (data.Address != null && !data.Address.Equals(unit.Address) &&
                !_commonSvc.NameAddressIsUnique<T>(data.Name, data.Address, null))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);
            if (data.ActualAddress != null && !data.ActualAddress.Equals(unit.ActualAddress) &&
                !_commonSvc.NameAddressIsUnique<T>(data.Name, null, data.ActualAddress))
                throw new BadRequestException(
                    $"{typeof(T).Name} {nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            return unit;
        }

        private static bool IsNoChanges(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var unitType = unit.GetType();
            var propertyInfo = unitType.GetProperties();
            foreach (var property in propertyInfo)
            {
                var unitProperty = unitType.GetProperty(property.Name).GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name).GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            var statUnit = unit as StatisticalUnit;
            if (statUnit == null) return true;
            var hstatUnit = (StatisticalUnit) hUnit;
            return hstatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId) 
                && hstatUnit.PersonsUnits.CompareWith(statUnit.PersonsUnits, p => p.PersonId);
        }
    }
}
