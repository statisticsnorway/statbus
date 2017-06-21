using System;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Helpers;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class ViewService
    {
        private readonly Common _commonSvc;
        private readonly UserService _userService;

        public ViewService(NSCRegDbContext dbContext)
        {
            _commonSvc = new Common(dbContext);
            _userService = new UserService(dbContext);
        }

        public async Task<object> GetUnitByIdAndType(int id, StatUnitTypes type, string userId, bool showDeleted)
        {
            var item = await _commonSvc.GetStatisticalUnitByIdAndType(id, type, showDeleted);
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return SearchItemVm.Create(item, item.UnitType, dataAttributes);
        }

        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId)
        {
            var item = id.HasValue
                ? await GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return StatUnitViewModelCreator.Create(item, dataAttributes);
        }

        private async Task<IStatisticalUnit> GetStatisticalUnitByIdAndType(int id, StatUnitTypes type, bool showDeleted)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return await _commonSvc.GetUnitById<LocalUnit>(id, showDeleted, query => query
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress)
                    );
                case StatUnitTypes.LegalUnit:
                    return await _commonSvc.GetUnitById<LegalUnit>(id, showDeleted, query => query
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress)
                        .Include(v => v.LocalUnits)
                    );
                case StatUnitTypes.EnterpriseUnit:
                    return await _commonSvc.GetUnitById<EnterpriseUnit>(id, showDeleted, query => query
                        .Include(x => x.LocalUnits)
                        .Include(x => x.LegalUnits)
                        .Include(v => v.ActivitiesUnits)
                        .ThenInclude(v => v.Activity)
                        .ThenInclude(v => v.ActivityRevxCategory)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress));
                case StatUnitTypes.EnterpriseGroup:
                    return await _commonSvc.GetUnitById<EnterpriseGroup>(id, showDeleted, query => query
                        .Include(x => x.LegalUnits)
                        .Include(x => x.EnterpriseUnits)
                        .Include(v => v.Address)
                        .Include(v => v.ActualAddress));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        private static IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
            => (IStatisticalUnit) Activator.CreateInstance(
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(type));
    }
}
