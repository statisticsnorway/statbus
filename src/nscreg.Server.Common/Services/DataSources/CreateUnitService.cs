using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Common.Services.DataSources
{
    public class CreateUnitService
    {
        private readonly StatisticalUnit _unit;
        private readonly string _userId;
        private readonly StatUnitCheckPermissionsHelper _helper;
        private bool _unitIsNew;
        private readonly NSCRegDbContext _dbContext;
        //private readonly StatUnitAnalysisRules _statUnitAnalysisRules;
        //private readonly DbMandatoryFields _mandatoryFields;
        private readonly UserService _userService;
        private readonly StatUnit.Common _commonSvc;
        //private readonly ValidationSettings _validationSettings;
        private readonly DataAccessService _dataAccessService;
       // private readonly bool _shouldAnalyze;

        public CreateUnitService(NSCRegDbContext dbContext, StatisticalUnit unit, bool unitIsNew, string userId)
        {
            _userId = userId;
            _unit = unit;
            _helper = new StatUnitCheckPermissionsHelper(dbContext);
            _unitIsNew = unitIsNew;
            _dbContext = dbContext;
           //_statUnitAnalysisRules = statUnitAnalysisRules;
            //_mandatoryFields = mandatoryFields;
            _userService = new UserService(dbContext);
            _commonSvc = new StatUnit.Common(dbContext);
            //_validationSettings = validationSettings;
            _dataAccessService = new DataAccessService(dbContext);
            //_shouldAnalyze = shouldAnalyze;
        }

        public async Task<Dictionary<string, string[]>> CreateLocalUnit()
        {
            _helper.CheckRegionOrActivityContains(_userId, _unit.Address?.RegionId, _unit.ActualAddress?.RegionId,
                _unit.PostalAddress?.RegionId, _unit.Activities.Select(x => x.ActivityCategoryId).ToList());

            if (_dataAccessService.CheckWritePermissions(_userId, StatUnitTypes.LocalUnit))
            {
                return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new[] { nameof(Resource.Error403) } } };
            }
            await _commonSvc.InitializeDataAccessAttributes(_userService, _unit, _userId, StatUnitTypes.LocalUnit);

            _unit.UserId = _userId;

            var helper = new StatUnitCreationHelper(_dbContext);
            await helper.CheckElasticConnect();

            await helper.CreateLocalUnit(_unit as LocalUnit);

            return null;
        }

        public async Task<Dictionary<string, string[]>> CreateLegalUnit()
        {
            _helper.CheckRegionOrActivityContains(_userId, _unit.Address?.RegionId, _unit.ActualAddress?.RegionId,
                _unit.PostalAddress?.RegionId, _unit.Activities.Select(x => x.ActivityCategoryId).ToList());

            if (_dataAccessService.CheckWritePermissions(_userId, StatUnitTypes.LocalUnit))
            {
                return new Dictionary<string, string[]> { { nameof(UserAccess.UnauthorizedAccess), new[] { nameof(Resource.Error403) } } };
            }
            await _commonSvc.InitializeDataAccessAttributes(_userService, _unit, _userId, StatUnitTypes.LocalUnit);

            _unit.UserId = _userId;

            var helper = new StatUnitCreationHelper(_dbContext);
            await helper.CheckElasticConnect();

            await helper.CreateLegalWithEnterpriseAndLocal(_unit as LegalUnit);

            return null;
        }



    }
}
