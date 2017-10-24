using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
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

                var statUnits = data.StatUnits ?? new List<StatUnitM>();
                foreach (var unitM in statUnits)
                {
                    if (unitM.StatRegId == null)
                        unit.StatisticalUnits.Add(new PersonStatisticalUnit
                        {
                            StatUnitId = unitM.StatRegId,
                            GroupUnitId = null,
                            PersonId = null,
                            PersonType = unitM.Role
                        });
                    else
                        unit.StatisticalUnits.Add(new PersonStatisticalUnit
                        {
                            GroupUnitId = unitM.GroupRegId,
                            StatUnitId = null,
                            PersonId = null,
                            PersonType = unitM.Role
                        });
                }

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
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (localUnit.LegalUnitId == null || localUnit.LegalUnitId == 0)
                    {
                        // Create corresponding legal unit
                        var legalUnit = new LegalUnit();
                        Mapper.Map(localUnit, legalUnit);

                        if ((localUnit.AddressId == 0 || localUnit.AddressId == null) && localUnit.Address != null)
                        {
                            var address = _dbContext.Address.Add(localUnit.Address).Entity;
                            await _dbContext.SaveChangesAsync();

                            localUnit.AddressId = address.Id;
                            legalUnit.AddressId = address.Id;
                        }

                        if ((localUnit.ActualAddressId == 0 || localUnit.ActualAddressId == null) && localUnit.ActualAddress != null)
                        {
                            var actualAddress = _dbContext.Address.Add(localUnit.ActualAddress).Entity;
                            await _dbContext.SaveChangesAsync();

                            localUnit.ActualAddressId = actualAddress.Id;
                            legalUnit.ActualAddressId = actualAddress.Id;
                        }

                        _dbContext.LegalUnits.Add(legalUnit);
                        
                        // Create new activities and persons
                        localUnit.Activities.ForEach(x =>
                        {
                            _dbContext.Activities.Add(x);
                        });
                        localUnit.Persons.Where(x => x.Id == 0).ForEach(x =>
                        {
                            _dbContext.Persons.Add(x);
                        });
                        await _dbContext.SaveChangesAsync();

                        localUnit.LegalUnitId = legalUnit.RegId;
                        _dbContext.LocalUnits.Add(localUnit);
                        await _dbContext.SaveChangesAsync();
                        
                        // Reference legal unit to local unit's activities and persons
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
                                PersonType = x.Role
                            });
                        });
                        legalUnit.HistoryLocalUnitIds = localUnit.RegId.ToString();
                        _dbContext.LegalUnits.Update(legalUnit);

                        await _dbContext.SaveChangesAsync();
                    }
                    else
                    {
                        _dbContext.LocalUnits.Add(localUnit);
                        await _dbContext.SaveChangesAsync();
                    }
                   
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }

        private async Task CreateLegalWithEnterprise(LegalUnit legalUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (legalUnit.EnterpriseUnitRegId == null || legalUnit.EnterpriseUnitRegId == 0)
                    {
                        var enterpriseUnit = new EnterpriseUnit();
                        Mapper.Map(legalUnit, enterpriseUnit);

                        if ((legalUnit.AddressId == 0 || legalUnit.AddressId == null) && legalUnit.Address != null)
                        {
                            var address = _dbContext.Address.Add(legalUnit.Address).Entity;
                            await _dbContext.SaveChangesAsync();

                            legalUnit.AddressId = address.Id;
                            enterpriseUnit.AddressId = address.Id;
                        }

                        if ((legalUnit.ActualAddressId == 0 || legalUnit.ActualAddressId == null) && legalUnit.ActualAddress != null)
                        {
                            var actualAddress = _dbContext.Address.Add(legalUnit.ActualAddress).Entity;
                            await _dbContext.SaveChangesAsync();

                            legalUnit.ActualAddressId = actualAddress.Id;
                            enterpriseUnit.ActualAddressId = actualAddress.Id;
                        }

                        _dbContext.EnterpriseUnits.Add(enterpriseUnit);

                        legalUnit.Activities.ForEach(x =>
                        {
                            _dbContext.Activities.Add(x);
                        });
                        legalUnit.Persons.Where(x => x.Id == 0).ForEach(x =>
                        {
                            _dbContext.Persons.Add(x);
                        });
                        await _dbContext.SaveChangesAsync();

                        legalUnit.EnterpriseUnitRegId = enterpriseUnit.RegId;
                        _dbContext.LegalUnits.Add(legalUnit);
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
                                PersonType = x.Role
                            });
                        });
                        enterpriseUnit.HistoryLegalUnitIds = legalUnit.RegId.ToString();
                        _dbContext.EnterpriseUnits.Update(enterpriseUnit);

                        await _dbContext.SaveChangesAsync();
                    }
                    else
                    {
                        _dbContext.LegalUnits.Add(legalUnit);
                        await _dbContext.SaveChangesAsync();
                    }
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }

        private async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId == 0)
                    {
                        var enterpriseGroup = new EnterpriseGroup();
                        Mapper.Map(enterpriseUnit, enterpriseGroup);

                        if ((enterpriseUnit.AddressId == 0 || enterpriseUnit.AddressId == null) && enterpriseUnit.Address != null)
                        {
                            var address = _dbContext.Address.Add(enterpriseUnit.Address).Entity;
                            await _dbContext.SaveChangesAsync();

                            enterpriseUnit.AddressId = address.Id;
                            enterpriseGroup.AddressId = address.Id;
                        }

                        if ((enterpriseUnit.ActualAddressId == 0 || enterpriseUnit.ActualAddressId == null) && enterpriseUnit.ActualAddress != null)
                        {
                            var actualAddress = _dbContext.Address.Add(enterpriseUnit.ActualAddress).Entity;
                            await _dbContext.SaveChangesAsync();

                            enterpriseUnit.ActualAddressId = actualAddress.Id;
                            enterpriseGroup.ActualAddressId = actualAddress.Id;
                        }

                        _dbContext.EnterpriseGroups.Add(enterpriseGroup);

                        enterpriseUnit.Activities.ForEach(x =>
                        {
                            _dbContext.Activities.Add(x);
                        });
                        enterpriseUnit.Persons.Where(x => x.Id == 0).ForEach(x =>
                        {
                            _dbContext.Persons.Add(x);
                        });
                        await _dbContext.SaveChangesAsync();

                        enterpriseUnit.EntGroupId = enterpriseGroup.RegId;
                        _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                        await _dbContext.SaveChangesAsync();
                        
                        enterpriseGroup.HistoryEnterpriseUnitIds = enterpriseUnit.RegId.ToString();
                        _dbContext.EnterpriseGroups.Update(enterpriseGroup);

                        await _dbContext.SaveChangesAsync();
                    }
                    else
                    {
                        _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                        await _dbContext.SaveChangesAsync();
                    }
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
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
