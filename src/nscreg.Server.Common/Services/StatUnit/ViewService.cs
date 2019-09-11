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
using System.Reflection;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using AutoMapper;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class ViewService
    {
        private readonly Common _commonSvc;
        private readonly UserService _userService;
        private readonly RegionService _regionService;
        private readonly NSCRegDbContext _context;
        private readonly DbMandatoryFields _mandatoryFields;

        public ViewService(NSCRegDbContext dbContext, DbMandatoryFields mandatoryFields)
        {
            _commonSvc = new Common(dbContext);
            _userService = new UserService(dbContext);
            _regionService = new RegionService(dbContext);
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
            if (item == null) throw new BadRequestException(nameof(Resource.NotFoundMessage));
            async Task FillRegionParents(Address address)
            {
                if (address?.Region?.ParentId == null)
                    return;
                address.Region.Parent = await _regionService.GetRegionParents(address.Region.ParentId.Value);
            }

            await FillRegionParents(item.Address);
            await FillRegionParents(item.ActualAddress);
            await FillRegionParents(item.PostalAddress);

            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            foreach (var person in item.PersonsUnits)
            {
                if (person.PersonTypeId != null) person.Person.Role = (int) person.PersonTypeId;
            }
            return SearchItemVm.Create(item, item.UnitType, dataAttributes.GetReadablePropNames());
        }

        /// <summary>
        /// Метод получение вью модели
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="userId">Id пользователя</param>
        /// <param name="ignoredActions"></param>
        /// <returns></returns>
        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId, ActionsEnum ignoredActions)
        {
            bool isEmployee = await _userService.IsInRoleAsync(userId, DefaultRoleNames.Employee);
            var item = id.HasValue
                ? await _commonSvc.GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);

            if (item == null) throw new BadRequestException(nameof(Resource.NotFoundMessage));
            
            if ((ignoredActions == ActionsEnum.Edit) && isEmployee)
            {
                var helper = new StatUnitCheckPermissionsHelper(_context);
                var mappedItem = new ElasticStatUnit();
                Mapper.Map(item, mappedItem);
                helper.CheckRegionOrActivityContains(userId, mappedItem.RegionIds, mappedItem.ActivityCategoryIds);
            }
            
            var dataAccess = await _userService.GetDataAccessAttributes(userId, item.UnitType);

            var config = type == StatUnitTypes.EnterpriseGroup
                ? _mandatoryFields.EnterpriseGroup
                : (object) _mandatoryFields.StatUnit;
            var mandatoryDict = config.GetType().GetProperties().ToDictionary(x => x.Name, GetValueFrom(config));
            if (type != StatUnitTypes.EnterpriseGroup)
            {
                object subConfig;
                switch (type)
                {
                    case StatUnitTypes.LocalUnit:
                        subConfig = _mandatoryFields.LocalUnit;
                        break;
                    case StatUnitTypes.LegalUnit:
                        subConfig = _mandatoryFields.LegalUnit;
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        subConfig = _mandatoryFields.Enterprise;
                        break;
                    default: throw new Exception("bad statunit type");
                }
                var getValue = GetValueFrom(subConfig);
                subConfig.GetType().GetProperties().ForEach(x => mandatoryDict[x.Name] = getValue(x));
            }

            return StatUnitViewModelCreator.Create(item, dataAccess, mandatoryDict, ignoredActions);

            Func<PropertyInfo, bool> GetValueFrom(object source) => prop =>
            {
                var value = prop.GetValue(source);
                return value is bool b && b;
            };
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
            var unit = await _context.StatisticalUnits.FirstOrDefaultAsync(x =>
                x.RegId == id || x.IsDeleted != showDeleted);
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
            => (IStatisticalUnit) Activator.CreateInstance(StatisticalUnitsTypeHelper.GetStatUnitMappingType(type));

        public async Task<UnitLookupVm> GetStatUnitById(int id)
        {
            var unit = await _context.StatisticalUnits.FirstOrDefaultAsync(x => x.RegId == id && x.IsDeleted == false);
            return new UnitLookupVm
            {
                Id = unit.RegId,
                Type = unit.UnitType,
                Name = unit.Name,
            };
        }

        public async Task<CodeLookupVm> GetSectorCodeNameBySectorId(int sectorCodeId)
        {
            var sectorCode = await _context.SectorCodes.FirstOrDefaultAsync(x => x.Id == sectorCodeId);
            return sectorCode != null
                ? new CodeLookupVm {Id = sectorCode.Id, Code = sectorCode.Code, Name = sectorCode.Name, NameLanguage1 = sectorCode.NameLanguage1, NameLanguage2 = sectorCode.NameLanguage2}
                : new CodeLookupVm();
        }

        public async Task<CodeLookupVm> GetLegalFormCodeNameByLegalFormId(int legalFormId)
        {
            var legalForm = await _context.LegalForms.FirstOrDefaultAsync(x => x.Id == legalFormId);
            return legalForm != null
                ? new CodeLookupVm { Id = legalForm.Id, Code = legalForm.Code, Name = legalForm.Name, NameLanguage1 = legalForm.NameLanguage1, NameLanguage2 = legalForm.NameLanguage2 }
                : new CodeLookupVm();
        }
    }
}
