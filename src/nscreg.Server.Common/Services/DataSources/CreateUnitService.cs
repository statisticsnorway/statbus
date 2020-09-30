using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Services.DataSources
{
    public class CreateUnitService
    {
        private readonly string _userId;

        private readonly StatUnitCreationHelper _creationHelper;
        public CreateUnitService(NSCRegDbContext dbContext, string userId, ElasticService service)
        {
            _userId = userId;
            _creationHelper = new StatUnitCreationHelper(dbContext, service);
        }

        public async Task CreateLocalUnit(LocalUnit unit)
        {
            //TODO: Перенести в Populate все проверки на доступ и права
            //_helper.CheckRegionOrActivityContains(_userId, _unit.Address?.RegionId, _unit.ActualAddress?.RegionId,
            //    _unit.PostalAddress?.RegionId, _unit.Activities.Select(x => x.ActivityCategoryId).ToList());

            //if (_dataAccessService.CheckWritePermissions(_userId, StatUnitTypes.LocalUnit))
            //{
            //    return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new[] { nameof(Resource.Error403) } } };
            //}
            //await _commonSvc.InitializeDataAccessAttributes(_userService, _unit, _userId, StatUnitTypes.LocalUnit);

            unit.UserId = _userId;
            await _creationHelper.CreateLocalUnit(unit);
        }

        public async Task CreateLegalUnit(LegalUnit unit)
        {
            //TODO: Перенести в Populate все проверки на доступ и права
            //_helper.CheckRegionOrActivityContains(_userId, _unit.Address?.RegionId, _unit.ActualAddress?.RegionId,
            //    _unit.PostalAddress?.RegionId, _unit.Activities.Select(x => x.ActivityCategoryId).ToList());

            //if (_dataAccessService.CheckWritePermissions(_userId, StatUnitTypes.LocalUnit))
            //{
            //    return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new[] { nameof(Resource.Error403) } } };
            //}
            //await _commonSvc.InitializeDataAccessAttributes(_userService, _unit, _userId, StatUnitTypes.LocalUnit);

            unit.UserId = _userId;
            await _creationHelper.CreateLegalWithEnterpriseAndLocal(unit);
        }

        public async Task CreateEnterpriseUnit(EnterpriseUnit unit)
        {
            unit.UserId = _userId;

            //TODO: Перенести в Populate все проверки на доступ и права
            //var helper = new StatUnitCheckPermissionsHelper(_dbContext);
            //helper.CheckRegionOrActivityContains(userId, data.Address?.RegionId, data.ActualAddress?.RegionId, data.PostalAddress?.RegionId, data.Activities.Select(x => x.ActivityCategoryId).ToList());
            await _creationHelper.CreateEnterpriseWithGroup(unit);
        }
    }
}
