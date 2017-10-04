using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Extensions;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Enums;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис создания
    /// </summary>
    public class CreateService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly UserService _userService;
        private readonly Common _commonSvc;

        public CreateService(NSCRegDbContext dbContext, StatUnitAnalysisRules statUnitAnalysisRules, DbMandatoryFields mandatoryFields)
        {
            _dbContext = dbContext;
            _statUnitAnalysisRules = statUnitAnalysisRules;
            _mandatoryFields = mandatoryFields;
            _userService = new UserService(dbContext);
            _commonSvc = new Common(dbContext);
        }

        /// <summary>
        /// Метод создания правовой единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLegalUnit(LegalUnitCreateM data, string userId)
            => await CreateUnitContext<LegalUnit, LegalUnitCreateM>(data, userId, unit =>
            {
                if (Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
                {
                    var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId));
                    foreach (var localUnit in localUnits)
                    {
                        unit.LocalUnits.Add(localUnit);
                    }

                    if (data.LocalUnits != null)
                        unit.HistoryLocalUnitIds = string.Join(",", data.LocalUnits);
                }
                return Task.CompletedTask;
            });

        /// <summary>
        /// Метод создания местной единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateLocalUnit(LocalUnitCreateM data, string userId)
            => await CreateUnitContext<LocalUnit, LocalUnitCreateM>(data, userId, null);

        /// <summary>
        /// Метод создания предприятия
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
            => await CreateUnitContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }

                if (data.LegalUnits != null)
                    unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);

                return Task.CompletedTask;
            });

        /// <summary>
        /// Метод создания группы предприятия
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<Dictionary<string, string[]>> CreateEnterpriseGroup(EnterpriseGroupCreateM data, string userId)
            => await CreateContext<EnterpriseGroup, EnterpriseGroupCreateM>(data, userId, unit =>
            {
                if (Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId))
                        .ToList();
                    foreach (var enterprise in enterprises)
                    {
                        unit.EnterpriseUnits.Add(enterprise);
                    }

                    if (data.EnterpriseUnits != null)
                        unit.HistoryEnterpriseUnitIds = string.Join(",", data.EnterpriseUnits);
                }
                
                return Task.CompletedTask;
            });

        /// <summary>
        /// Метод создания контекста стат. единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> CreateUnitContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : StatUnitModelBase
            where TUnit : StatisticalUnit, new()
            => await CreateContext<TUnit, TModel>(data, userId, async unit =>
            {
                if (Common.HasAccess<TUnit>(data.DataAccess, v => v.Activities))
                {
                    var activitiesList = data.Activities ?? new List<ActivityM>();

                    //Get Ids for codes
                    var activityService = new CodeLookupService<ActivityCategory>(_dbContext);
                    var codesList = activitiesList.Select(v => v.ActivityRevxCategory.Code).ToList();

                    var codesLookup = new CodeLookupProvider<CodeLookupVm>(
                        nameof(Resource.ActivityCategoryLookup),
                        await activityService.List(false, v => codesList.Contains(v.Code))
                    );

                    unit.ActivitiesUnits.AddRange(activitiesList.Select(v =>
                        {
                            var activity = Mapper.Map<ActivityM, Activity>(v);
                            activity.Id = 0;
                            activity.ActivityRevx = codesLookup.Get(v.ActivityRevxCategory.Code).Id;
                            activity.UpdatedBy = userId;
                            return new ActivityStatisticalUnit {Activity = activity};
                        }
                    ));
                }

                var personList = data.Persons ?? new List<PersonM>();

                unit.PersonsUnits.AddRange(personList.Select(v =>
                {
                    var person = Mapper.Map<PersonM, Person>(v);
                    person.Id = 0;
                    return new PersonStatisticalUnit {Person = person, PersonType = person.Role};
                }));

                if (work != null)
                {
                    await work(unit);
                }
            });

        /// <summary>
        /// Метод создания контекста
        /// </summary>
        /// <param name="data">Данные</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="work">В работе</param>
        /// <returns></returns>
        private async Task<Dictionary<string, string[]>> CreateContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = new TUnit();
            await _commonSvc.InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);
            Mapper.Map(data, unit);
            _commonSvc.AddAddresses<TUnit>(unit, data);

            if (!_commonSvc.NameAddressIsUnique<TUnit>(data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            if (work != null)
            {
                await work(unit);
            }

            unit.UserId = userId;

            IStatUnitAnalyzeService analysisService = new AnalyzeService(_dbContext, new StatUnitAnalyzer(_statUnitAnalysisRules, _mandatoryFields));
            var analyzeResult = analysisService.AnalyzeStatUnit(unit);
            if (analyzeResult.Messages.Any()) return analyzeResult.Messages;

            if (unit is LocalUnit)
                await CreateLocalWithLegal(unit as LocalUnit);
            else if (unit is LegalUnit)
                await CreateLegalWithEnterprise(unit as LegalUnit);
            else if (unit is EnterpriseUnit)
                await CreateEnterpriseWithGroup(unit as EnterpriseUnit);
            else if (unit is EnterpriseGroup)
                await CreateGroup(unit as EnterpriseGroup);

            return null;
        }

        private async Task CreateLocalWithLegal(LocalUnit localUnit)
        {
            if (localUnit.LegalUnitId == null)
            {
                var legalUnit = new LegalUnit
                {
                    Classified = localUnit.Classified,
                    ContactPerson = localUnit.ContactPerson,
                    DataSource = localUnit.DataSource,
                    EditComment = localUnit.EditComment,
                    EmailAddress = localUnit.EmailAddress,
                    Employees = localUnit.Employees,
                    EmployeesDate = localUnit.EmployeesDate,
                    EmployeesYear = localUnit.EmployeesYear,
                    RegistrationDate = localUnit.RegistrationDate,
                    EndPeriod = localUnit.EndPeriod,
                    ForeignParticipation = localUnit.ForeignParticipation,
                    ExternalId = localUnit.ExternalId,
                    ExternalIdDate = localUnit.ExternalIdDate,
                    ExternalIdType = localUnit.ExternalIdType,
                    FreeEconZone = localUnit.FreeEconZone,
                    InstSectorCodeId = localUnit.InstSectorCodeId,
                    WebAddress = localUnit.WebAddress,
                    TurnoverYear = localUnit.TurnoverYear,
                    TurnoverDate = localUnit.TurnoverDate,
                    Turnover = localUnit.Turnover,
                    TelephoneNo = localUnit.TelephoneNo,
                    TaxRegId = localUnit.TaxRegId,
                    TaxRegDate = localUnit.TaxRegDate,
                    SuspensionStart = localUnit.SuspensionStart,
                    SuspensionEnd = localUnit.SuspensionEnd,
                    StatusDate = localUnit.StatusDate,
                    StatId = localUnit.StatId,
                    StatIdDate = localUnit.StatIdDate,
                    ShortName = localUnit.ShortName,
                    StartPeriod = localUnit.StartPeriod,
                    ReorgTypeCode = localUnit.ReorgTypeCode,
                    ReorgReferences = localUnit.ReorgReferences,
                    ReorgDate = localUnit.ReorgDate,
                    RegistrationReason = localUnit.RegistrationReason,
                    RegIdDate = localUnit.RegIdDate,
                    RegId = localUnit.RegId,
                    RefNo = localUnit.RefNo,
                    PostalAddressId = localUnit.PostalAddressId,
                    ParentOrgLink = localUnit.ParentOrgLink,
                    NumOfPeopleEmp = localUnit.NumOfPeopleEmp,
                    Notes = localUnit.Notes,
                    Name = localUnit.Name,
                    LiqReason = localUnit.LiqReason,
                    LiqDate = localUnit.LiqDate,
                    LegalFormId = localUnit.LegalFormId,
                    IsDeleted = localUnit.IsDeleted,
                    ForeignParticipationCountryId = localUnit.ForeignParticipationCountryId,
                    ActualAddressId = localUnit.ActualAddressId,

                    MunCapitalShare = string.Empty,
                    Owner = string.Empty,
                    PrivCapitalShare = string.Empty,
                    StateCapitalShare = string.Empty,
                    TotalCapital = string.Empty,
                    ForeignCapitalShare = string.Empty,
                    ForeignCapitalCurrency = string.Empty,
                    HistoryLocalUnitIds = string.Empty,
                    Founders = string.Empty,
                    EntRegIdDate = DateTime.Now,
                    Market = false,
                    EnterpriseUnitRegId = null,
                    AddressId = localUnit.AddressId,
                    ChangeReason = ChangeReasons.Create
                };

                _dbContext.LegalUnits.Add(legalUnit);
                await _dbContext.SaveChangesAsync();

                localUnit.Activities.ForEach(x =>
                {
                    _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                    {
                        ActivityId = x.Id,
                        UnitId = legalUnit.RegId
                    });
                });
                localUnit.Persons.ForEach(x =>
                {
                    _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                    {
                        PersonId = x.Id,
                        UnitId = legalUnit.RegId,
                        PersonType =
                            _dbContext.PersonStatisticalUnits
                                .FirstOrDefault(pu => pu.PersonId == x.Id && pu.UnitId == localUnit.RegId)
                                .PersonType
                    });
                });
                localUnit.LegalUnitId = legalUnit.RegId;
            }

            _dbContext.LocalUnits.Add(localUnit);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private async Task CreateLegalWithEnterprise(LegalUnit legalUnit)
        {
            if (legalUnit.EnterpriseUnitRegId == null)
            {
                var enterpriseUnit = new EnterpriseUnit
                {
                    ActualAddressId = legalUnit.ActualAddressId,
                    AddressId = legalUnit.AddressId,
                    ChangeReason = ChangeReasons.Create,
                    Classified = legalUnit.Classified,
                    Commercial = false,
                    ContactPerson = legalUnit.ContactPerson,
                    DataSource = legalUnit.DataSource,
                    EditComment = legalUnit.EditComment,
                    EmailAddress = legalUnit.EmailAddress,
                    Employees = legalUnit.Employees,
                    EmployeesDate = legalUnit.EmployeesDate,
                    EmployeesYear = legalUnit.EmployeesYear,
                    EndPeriod = legalUnit.EndPeriod,
                    EntGroupId = null,
                    EntGroupIdDate = DateTime.Now,
                    ExternalIdDate = legalUnit.ExternalIdDate,
                    EntGroupRole = string.Empty,
                    ExternalId = legalUnit.ExternalId,
                    ExternalIdType = legalUnit.ExternalIdType,
                    ForeignCapitalCurrency = legalUnit.ForeignCapitalCurrency,
                    ForeignCapitalShare = legalUnit.ForeignCapitalShare,
                    ForeignParticipation = legalUnit.ForeignParticipation,
                    ForeignParticipationCountryId = legalUnit.ForeignParticipationCountryId,
                    FreeEconZone = legalUnit.FreeEconZone,
                    HistoryLegalUnitIds = string.Empty,
                    InstSectorCodeId = legalUnit.InstSectorCodeId,
                    IsDeleted = legalUnit.IsDeleted,
                    LegalFormId = legalUnit.LegalFormId,
                    LiqDate = legalUnit.LiqDate,
                    LiqReason = legalUnit.LiqReason,
                    WebAddress = legalUnit.WebAddress,
                    UserId = legalUnit.UserId,
                    TurnoverYear = legalUnit.TurnoverYear,
                    TurnoverDate = legalUnit.TurnoverDate,
                    Turnover = legalUnit.Turnover,
                    TotalCapital = legalUnit.TotalCapital,
                    TelephoneNo = legalUnit.TelephoneNo,
                    TaxRegId = legalUnit.TaxRegId,
                    TaxRegDate = legalUnit.TaxRegDate,
                    SuspensionStart = legalUnit.SuspensionStart,
                    SuspensionEnd = legalUnit.SuspensionEnd,
                    StatusDate = legalUnit.StatusDate,
                    Status = legalUnit.Status,
                    StateCapitalShare = legalUnit.StateCapitalShare,
                    StatIdDate = legalUnit.StatIdDate,
                    StatId = legalUnit.StatId,
                    StartPeriod = legalUnit.StartPeriod,
                    ShortName = legalUnit.ShortName,
                    ReorgTypeCode = legalUnit.ReorgTypeCode,
                    ReorgReferences = legalUnit.ReorgReferences,
                    ReorgDate = legalUnit.ReorgDate,
                    RegistrationReason = legalUnit.RegistrationReason,
                    RegistrationDate = legalUnit.RegistrationDate,
                    RegIdDate = legalUnit.RegIdDate,
                    RegId = legalUnit.RegId,
                    RefNo = legalUnit.RefNo,
                    PrivCapitalShare = legalUnit.PrivCapitalShare,
                    PostalAddressId = legalUnit.PostalAddressId,
                    ParentOrgLink = legalUnit.ParentOrgLink,
                    NumOfPeopleEmp = legalUnit.NumOfPeopleEmp,
                    Notes = legalUnit.Notes,
                    Name = legalUnit.Name,
                    MunCapitalShare = legalUnit.MunCapitalShare
                };

                _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                await _dbContext.SaveChangesAsync();

                legalUnit.Activities.ForEach(x =>
                {
                    _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                    {
                        ActivityId = x.Id,
                        UnitId = enterpriseUnit.RegId
                    });
                });
                legalUnit.Persons.ForEach(x =>
                {
                    _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                    {
                        PersonId = x.Id,
                        UnitId = enterpriseUnit.RegId,
                        PersonType =
                            _dbContext.PersonStatisticalUnits
                                .FirstOrDefault(pu => pu.PersonId == x.Id && pu.UnitId == legalUnit.RegId)
                                .PersonType
                    });
                });
                legalUnit.EnterpriseUnitRegId = enterpriseUnit.RegId;
            }
            _dbContext.LegalUnits.Add(legalUnit);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            if (enterpriseUnit.EntGroupId == null)
            {
                var enterpriseGroup = new EnterpriseGroup
                {
                    Name = enterpriseUnit.Name,
                    ActualAddressId = enterpriseUnit.ActualAddressId,
                    AddressId = enterpriseUnit.AddressId,
                    ChangeReason = ChangeReasons.Create,
                    ContactPerson = enterpriseUnit.ContactPerson,
                    DataSource = enterpriseUnit.DataSource,
                    EditComment = enterpriseUnit.EditComment,
                    EmailAddress = enterpriseUnit.EmailAddress,
                    Employees = enterpriseUnit.Employees,
                    EmployeesDate = enterpriseUnit.EmployeesDate,
                    EmployeesYear = enterpriseUnit.EmployeesYear,
                    WebAddress = enterpriseUnit.WebAddress,
                    UserId = enterpriseUnit.UserId,
                    TurnoverYear = enterpriseUnit.TurnoverYear,
                    TurnoverDate = enterpriseUnit.TurnoverDate,
                    Turnover = enterpriseUnit.Turnover,
                    TelephoneNo = enterpriseUnit.TelephoneNo,
                    TaxRegId = enterpriseUnit.TaxRegId,
                    TaxRegDate = enterpriseUnit.TaxRegDate,
                    SuspensionStart = enterpriseUnit.SuspensionStart,
                    SuspensionEnd = enterpriseUnit.SuspensionEnd,
                    StatusDate = enterpriseUnit.StatusDate ?? DateTime.Now,
                    Status = string.Empty,
                    StatIdDate = enterpriseUnit.StatIdDate,
                    StatId = enterpriseUnit.StatId,
                    StartPeriod = enterpriseUnit.StartPeriod,
                    ShortName = enterpriseUnit.ShortName,
                    ReorgTypeCode = enterpriseUnit.ReorgTypeCode,
                    ReorgReferences = enterpriseUnit.ReorgReferences,
                    ReorgDate = enterpriseUnit.ReorgDate,
                    RegistrationReason = enterpriseUnit.RegistrationReason,
                    RegistrationDate = enterpriseUnit.RegistrationDate,
                    RegMainActivityId = null,
                    RegIdDate = enterpriseUnit.RegIdDate,
                    PostalAddressId = enterpriseUnit.PostalAddressId,
                    Notes = enterpriseUnit.Notes,
                    NumOfPeopleEmp = enterpriseUnit.NumOfPeopleEmp,
                    LiqDateStart = null,
                    LiqReason = enterpriseUnit.LiqReason,
                    LiqDateEnd = null,
                    LegalFormId = enterpriseUnit.LegalFormId,
                    IsDeleted = enterpriseUnit.IsDeleted,
                    InstSectorCodeId = enterpriseUnit.InstSectorCodeId,
                    HistoryEnterpriseUnitIds = string.Empty,
                    ExternalIdType = enterpriseUnit.ExternalIdType,
                    ExternalIdDate = enterpriseUnit.ExternalIdDate,
                    ExternalId = enterpriseUnit.ExternalId,
                    EntGroupType = string.Empty,
                    EndPeriod = enterpriseUnit.EndPeriod
                };

                _dbContext.EnterpriseGroups.Add(enterpriseGroup);
                await _dbContext.SaveChangesAsync();

                enterpriseUnit.EntGroupId = enterpriseGroup.RegId;
            }
            _dbContext.EnterpriseUnits.Add(enterpriseUnit);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        private async Task CreateGroup(EnterpriseGroup enterpriseGroup)
        {
            _dbContext.EnterpriseGroups.Add(enterpriseGroup);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }
    }
}



