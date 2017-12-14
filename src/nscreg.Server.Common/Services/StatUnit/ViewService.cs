using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.OrgLinks;
using System.Linq;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class ViewService
    {
        private readonly Common _commonSvc;
        private readonly UserService _userService;
        private readonly NSCRegDbContext _context;
        private readonly DbMandatoryFields _mandatoryFields;

        public ViewService(NSCRegDbContext dbContext, DbMandatoryFields mandatoryFields)
        {
            _commonSvc = new Common(dbContext);
            _userService = new UserService(dbContext);
            _context = dbContext;
            _mandatoryFields = mandatoryFields;
        }

        /// <summary>
        /// Метод получения стат. единицы по Id и типу
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<object> GetUnitByIdAndType(int id, StatUnitTypes type, string userId, bool showDeleted)
        {
            var item = await _commonSvc.GetStatisticalUnitByIdAndType(id, type, showDeleted);
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            return SearchItemVm.Create(item, item.UnitType, dataAttributes.GetReadablePropNames());
        }

        /// <summary>
        /// Метод получение вью модели
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <returns></returns>
        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId)
        {
            var item = id.HasValue
                ? await _commonSvc.GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);
            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            var model = StatUnitViewModelCreator.Create(item, dataAttributes);

            if (type != StatUnitTypes.EnterpriseGroup)
            {
                model.Properties[9].IsRequired = _mandatoryFields.StatUnit.Address;
            }
            else
            {
                model.Properties[34].IsRequired = _mandatoryFields.EnterpriseGroup.Address;
            }
            
            return model;
        }

        /// <summary>
        /// Метод получения дерева организационной связи
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        public async Task<OrgLinksNode> GetOrgLinksTree(int id)
        {
            var root = OrgLinksNode.Create(await GetOrgLinkNode(id), await GetChildren(id));

            while (root.ParentOrgLink.HasValue)
            {
                root = OrgLinksNode.Create(
                    await GetOrgLinkNode(root.ParentOrgLink.Value),
                    new[] {root});
            }
            return root;

            async Task<StatisticalUnit> GetOrgLinkNode(int regId) => await
                _context.StatisticalUnits.FirstOrDefaultAsync(x => x.RegId == regId && !x.IsDeleted);

            async Task<IEnumerable<OrgLinksNode>> GetChildren(int regId) => await (await _context.StatisticalUnits
                    .Where(u => u.ParentOrgLink == regId && !u.IsDeleted).ToListAsync())
                .SelectAsync(async x => OrgLinksNode.Create(x, await GetChildren(x.RegId)));
        }

        /// <summary>
        /// Метод получения стат. единицы по Id
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public async Task<UnitLookupVm> GetById(int id, bool showDeleted = false)
        {
            var unit = await _context.StatisticalUnits.FirstOrDefaultAsync(x => x.RegId == id || x.IsDeleted != showDeleted);
            return new UnitLookupVm
            {
                Id = unit.RegId,
                Type = unit.UnitType,
                Name = unit.Name,
            };
        }

        /// <summary>
        /// Метод получения домена для типа по умолчанию
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <returns></returns>
        private static IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
            => (IStatisticalUnit) Activator.CreateInstance(
                StatisticalUnitsTypeHelper.GetStatUnitMappingType(type));

        public async Task<UnitLookupVm> GetOrgLinkById(int id)
        {
            var unit = await _context.StatisticalUnits.FirstOrDefaultAsync(x => x.RegId == id && x.IsDeleted == false);
            return new UnitLookupVm
            {
                Id = unit.RegId,
                Type = unit.UnitType,
                Name = unit.Name,
            };
        }

        public async Task<string> GetSectorCodeNameBySectorId(int sectorCodeId)
        {
            var sectorCode = await _context.SectorCodes.FirstOrDefaultAsync(x => x.Id == sectorCodeId);
            return sectorCode != null
                ? $"\"({sectorCode.Code}) {sectorCode.Name}\""
                : null;
        }

        public async Task<string> GetLegalFormCodeNameByLegalFormId(int legalFormId)
        {
            var legalForm = await _context.LegalForms.FirstOrDefaultAsync(x => x.Id == legalFormId);
            return legalForm != null
                ? $"\"({legalForm.Code}) {legalForm.Name}\""
                : null;
        }
    }
}
