using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Core;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Utilities.Extensions;
using static nscreg.Server.Services.StatUnit.Common;

namespace nscreg.Server.Services.StatUnit
{
    public class CreateService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;

        public CreateService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
        }

        public async Task CreateLegalUnit(LegalUnitCreateM data, string userId)
            => await CreateUnitContext<LegalUnit, LegalUnitCreateM>(data, userId, unit =>
            {
                if (HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
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

        public async Task CreateLocalUnit(LocalUnitCreateM data, string userId)
            => await CreateUnitContext<LocalUnit, LocalUnitCreateM>(data, userId, null);

        public async Task CreateEnterpriseUnit(EnterpriseUnitCreateM data, string userId)
            => await CreateUnitContext<EnterpriseUnit, EnterpriseUnitCreateM>(data, userId, unit =>
            {
                var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId)).ToList();
                foreach (var localUnit in localUnits)
                {
                    unit.LocalUnits.Add(localUnit);
                }
                var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                foreach (var legalUnit in legalUnits)
                {
                    unit.LegalUnits.Add(legalUnit);
                }
                return Task.CompletedTask;
            });

        public async Task CreateEnterpriseGroupUnit(EnterpriseGroupCreateM data, string userId)
            => await CreateContext<EnterpriseGroup, EnterpriseGroupCreateM>(data, userId, unit =>
            {
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
                {
                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId))
                        .ToList();
                    foreach (var enterprise in enterprises)
                    {
                        unit.EnterpriseUnits.Add(enterprise);
                    }
                }
                if (HasAccess<EnterpriseGroup>(data.DataAccess, v => v.LegalUnits))
                {
                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId)).ToList();
                    foreach (var legalUnit in legalUnits)
                    {
                        unit.LegalUnits.Add(legalUnit);
                    }
                }
                return Task.CompletedTask;
            });

        private async Task CreateUnitContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : StatUnitModelBase
            where TUnit : StatisticalUnit, new()
            => await CreateContext<TUnit, TModel>(data, userId, async unit =>
            {
                if (HasAccess<TUnit>(data.DataAccess, v => v.Activities))
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

                if (work != null)
                {
                    await work(unit);
                }
            });

        private async Task CreateContext<TUnit, TModel>(
            TModel data,
            string userId,
            Func<TUnit, Task> work)
            where TModel : IStatUnitM
            where TUnit : class, IStatisticalUnit, new()
        {
            var unit = new TUnit();
            await InitializeDataAccessAttributes(_userService, data, userId, unit.UnitType);
            Mapper.Map(data, unit);
            AddAddresses(_dbContext, unit, data);

            if (!NameAddressIsUnique<TUnit>(_dbContext, data.Name, data.Address, data.ActualAddress))
                throw new BadRequestException($"{nameof(Resource.AddressExcistsInDataBaseForError)} {data.Name}", null);

            if (work != null)
            {
                await work(unit);
            }

            unit.UserId = userId;

            _dbContext.Set<TUnit>().Add(unit);
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
