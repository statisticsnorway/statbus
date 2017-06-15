using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Models.StatUnits;

namespace nscreg.Server.Services.StatUnit
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
    }
}
