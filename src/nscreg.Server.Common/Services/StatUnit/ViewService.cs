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
using nscreg.Server.Common.Services.Contracts;
using System.IO;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class ViewService
    {
        private readonly CommonService _commonSvc;
        private readonly IUserService _userService;
        private readonly RegionService _regionService;
        private readonly NSCRegDbContext _context;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly StatUnitCheckPermissionsHelper _statUnitCheckPermissionsHelper;
        private readonly IMapper _mapper;

        private const string _separator = "\t";

        public ViewService(NSCRegDbContext context, CommonService commonSvc,
            IUserService userService, RegionService regionService, DbMandatoryFields mandatoryFields,
            StatUnitCheckPermissionsHelper statUnitCheckPermissionsHelper,
            IMapper mapper)
        {
            _commonSvc = commonSvc;
            _userService = userService;
            _regionService = regionService;
            _context = context;
            _mandatoryFields = mandatoryFields;
            _statUnitCheckPermissionsHelper = statUnitCheckPermissionsHelper;
            _mapper = mapper;
        }

        /// <summary>
        /// Method for getting stat. units by Id and type
        /// </summary>
        /// <param name = "id"> Id stat. units </param>
        /// <param name = "type"> Type of stat. units </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "showDeleted"> Distance flag </param>
        /// <returns> </returns>
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

            await FillRegionParents(item.ActualAddress);
            await FillRegionParents(item.PostalAddress);

            var dataAttributes = await _userService.GetDataAccessAttributes(userId, item.UnitType);
            foreach (var person in item.PersonsUnits)
            {
                if (person.PersonTypeId != null) person.Person.Role = (int)person.PersonTypeId;
            }
            return SearchItemVm.Create(item, item.UnitType, dataAttributes.GetReadablePropNames());
        }

        /// <summary>
        /// Method to get view model
        /// </summary>
        /// <param name = "id"> Id stat. units </param>
        /// <param name = "type"> Type of stat. units </param>
        /// <param name = "userId"> User Id </param>
        /// <param name = "ignoredActions"> </param>
        /// <returns> </returns>
        public async Task<StatUnitViewModel> GetViewModel(int? id, StatUnitTypes type, string userId, ActionsEnum ignoredActions)
        {
            bool isEmployee = await _userService.IsInRoleAsync(userId, DefaultRoleNames.Employee);
            var item = id.HasValue
                ? await _commonSvc.GetStatisticalUnitByIdAndType(id.Value, type, false)
                : GetDefaultDomainForType(type);

            if (item == null) throw new BadRequestException(nameof(Resource.NotFoundMessage));

            if ((ignoredActions == ActionsEnum.Edit) && isEmployee)
            {
                var mappedItem = new ElasticStatUnit();
                _mapper.Map(item, mappedItem);
                _statUnitCheckPermissionsHelper.CheckRegionOrActivityContains(userId, mappedItem.RegionIds, mappedItem.ActivityCategoryIds);
            }

            var dataAccess = await _userService.GetDataAccessAttributes(userId, item.UnitType);

            var config = type == StatUnitTypes.EnterpriseGroup
                ? _mandatoryFields.EnterpriseGroup
                : (object)_mandatoryFields.StatUnit;
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

            //The LegalUnits field of the EnterpriseUnit type is required by business logic
            if (type == StatUnitTypes.EnterpriseUnit && mandatoryDict.ContainsKey("LegalUnits"))
                mandatoryDict["LegalUnits"] = true;

            return StatUnitViewModelCreator.Create(item, dataAccess, mandatoryDict, ignoredActions);

            Func<PropertyInfo, bool> GetValueFrom(object source) => prop =>
            {
                var value = prop.GetValue(source);
                return value is bool b && b;
            };
        }

        /// <summary>
        /// Method for obtaining a tree of organizational communication
        /// </summary>
        /// <param name = "id"> Id stat. units </param>
        /// <returns> </returns>
        public async Task<OrgLinksNode> GetOrgLinksTree(int id)
        {
            var root = OrgLinksNode.Create(await GetOrgLinkNode(id), await GetChildren(id));

            while (root.ParentOrgLink.HasValue)
            {
                root = OrgLinksNode.Create(
                    await GetOrgLinkNode(root.ParentOrgLink.Value),
                    new[] { root });
            }
            return root;

            async Task<StatisticalUnit> GetOrgLinkNode(int regId) => await
                _context.StatisticalUnits.FirstOrDefaultAsync(x => x.RegId == regId && !x.IsDeleted);

            async Task<IEnumerable<OrgLinksNode>> GetChildren(int regId) => await (await _context.StatisticalUnits
                    .Where(u => u.ParentOrgLink == regId && !u.IsDeleted).ToListAsync())
                .SelectAsync(async x => OrgLinksNode.Create(x, await GetChildren(x.RegId)));
        }

        /// <summary>
        /// Method for getting stat. units by id
        /// </summary>
        /// <param name = "id"> Id stat. units </param>
        /// <param name = "showDeleted"> Distance flag </param>
        /// <returns> </returns>
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
        /// The method of obtaining the domain for the default type
        /// </summary>
        /// <param name = "type"> Type of stat. units </param>
        /// <returns> </returns>
        private static IStatisticalUnit GetDefaultDomainForType(StatUnitTypes type)
            => (IStatisticalUnit)Activator.CreateInstance(StatisticalUnitsTypeHelper.GetStatUnitMappingType(type));

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
                ? new CodeLookupVm { Id = sectorCode.Id, Code = sectorCode.Code, Name = sectorCode.Name, NameLanguage1 = sectorCode.NameLanguage1, NameLanguage2 = sectorCode.NameLanguage2 }
                : new CodeLookupVm();
        }

        public async Task<CodeLookupVm> GetLegalFormCodeNameByLegalFormId(int legalFormId)
        {
            var legalForm = await _context.LegalForms.FirstOrDefaultAsync(x => x.Id == legalFormId);
            return legalForm != null
                ? new CodeLookupVm { Id = legalForm.Id, Code = legalForm.Code, Name = legalForm.Name, NameLanguage1 = legalForm.NameLanguage1, NameLanguage2 = legalForm.NameLanguage2 }
                : new CodeLookupVm();
        }

        public async Task<byte[]> DownloadStatUnitEnterprise()
        {
            var records = _context.StatUnitEnterprise_2021.AsNoTracking().AsAsyncEnumerable();
            using var mem = new MemoryStream();
            using var writer = new StreamWriter(mem);

            writer.Write($"StatId{_separator} ");
            writer.Write($"Oblast{_separator} ");
            writer.Write($"Rayon{_separator} ");
            writer.Write($"ActCat_section_code{_separator} ");
            writer.Write($"ActCat_section_desc{_separator} ");
            writer.Write($"ActCat_2dig_code{_separator} ");
            writer.Write($"ActCat_2dig_desc{_separator} ");
            writer.Write($"ActCat_3dig_code{_separator} ");
            writer.Write($"ActCat_3dig_desc{_separator} ");
            writer.Write($"LegalForm_code{_separator} ");
            writer.Write($"LegalForm_desc{_separator} ");
            writer.Write($"InstSectorCode_level1{_separator} ");
            writer.Write($"InstSectorCode_level1_desc{_separator} ");
            writer.Write($"InstSectorCode_level2{_separator} ");
            writer.Write($"InstSectorCode_level2_desc{_separator} ");
            writer.Write($"SizeCode{_separator} ");
            writer.Write($"SizeDesc{_separator} ");
            writer.Write($"Turnover{_separator} ");
            writer.Write($"Employees{_separator} ");
            writer.Write($"NumOfPeopleEmp{_separator} ");
            writer.Write($"RegistrationDate{_separator} ");
            writer.Write($"LiqDate{_separator} ");
            writer.Write($"StatusCode{_separator} ");
            writer.Write($"StatusDesc{_separator} ");
            writer.Write($"Sex");
            writer.Write(Environment.NewLine);

            await foreach (var record in records)
            {
                WriteStringToStream(writer, record.StatId);
                WriteNullableToStream(writer, record.Oblast);
                WriteNullableToStream(writer, record.Rayon);
                WriteStringToStream(writer, record.ActCat_section_code);
                WriteStringToStream(writer, record.ActCat_section_desc);
                WriteStringToStream(writer, record.ActCat_2dig_code);
                WriteStringToStream(writer, record.ActCat_2dig_desc);
                WriteStringToStream(writer, record.ActCat_3dig_code);
                WriteStringToStream(writer, record.ActCat_3dig_desc);
                WriteStringToStream(writer, record.LegalForm_code);
                WriteStringToStream(writer, record.LegalForm_desc);
                WriteStringToStream(writer, record.InstSectorCode_level1);
                WriteStringToStream(writer, record.InstSectorCode_level1_desc);
                WriteStringToStream(writer, record.InstSectorCode_level2);
                WriteStringToStream(writer, record.InstSectorCode_level2_desc);
                WriteNullableToStream(writer, record.SizeCode);
                WriteStringToStream(writer, record.SizeDesc);
                WriteNullableToStream(writer, record.Turnover);
                WriteNullableToStream(writer, record.Employees);
                WriteNullableToStream(writer, record.NumOfPeopleEmp);
                WriteNullableToStream(writer, record.RegistrationDate);
                WriteNullableToStream(writer, record.LiqDate);
                WriteStringToStream(writer, record.StatusCode);
                WriteStringToStream(writer, record.StatusDesc);
                WriteNullableToStream(writer, record.Sex, Environment.NewLine);
            }

            writer.Flush();
            return mem.ToArray();
        }

        private static void WriteStringToStream(StreamWriter writer, string value, string separator = _separator)
        {
            if (!string.IsNullOrWhiteSpace(value))
                writer.Write(value);
            writer.Write(separator);
        }

        private static void WriteNullableToStream<T>(StreamWriter writer, Nullable<T> value, string separator = _separator) where T : struct
        {
            if (value.HasValue)
                writer.Write(value.Value.ToString());
            writer.Write(separator);
        }

        public async Task<byte[]> DownloadStatUnitLocal()
        {
            var records = _context.StatUnitLocal_2021.AsNoTracking().AsAsyncEnumerable();
            using var mem = new MemoryStream();
            using var writer = new StreamWriter(mem);

            writer.Write($"StatId{_separator} ");
            writer.Write($"Oblast{_separator} ");
            writer.Write($"Rayon{_separator} ");
            writer.Write($"ActCat_section_code{_separator} ");
            writer.Write($"ActCat_section_desc{_separator} ");
            writer.Write($"ActCat_2dig_code{_separator} ");
            writer.Write($"ActCat_2dig_desc{_separator} ");
            writer.Write($"ActCat_3dig_code{_separator} ");
            writer.Write($"ActCat_3dig_desc{_separator} ");
            writer.Write($"LegalForm_code{_separator} ");
            writer.Write($"LegalForm_desc{_separator} ");
            writer.Write($"InstSectorCode_level1{_separator} ");
            writer.Write($"InstSectorCode_level1_desc{_separator} ");
            writer.Write($"InstSectorCode_level2{_separator} ");
            writer.Write($"InstSectorCode_level2_desc{_separator} ");
            writer.Write($"SizeCode{_separator} ");
            writer.Write($"SizeDesc{_separator} ");
            writer.Write($"Turnover{_separator} ");
            writer.Write($"Employees{_separator} ");
            writer.Write($"NumOfPeopleEmp{_separator} ");
            writer.Write($"RegistrationDate{_separator} ");
            writer.Write($"LiqDate{_separator} ");
            writer.Write($"StatusCode{_separator} ");
            writer.Write($"StatusDesc{_separator} ");
            writer.Write($"Sex");
            writer.Write(Environment.NewLine);

            await foreach (var record in records)
            {
                WriteStringToStream(writer, record.StatId);
                WriteNullableToStream(writer, record.Oblast);
                WriteNullableToStream(writer, record.Rayon);
                WriteStringToStream(writer, record.ActCat_section_code);
                WriteStringToStream(writer, record.ActCat_section_desc);
                WriteStringToStream(writer, record.ActCat_2dig_code);
                WriteStringToStream(writer, record.ActCat_2dig_desc);
                WriteStringToStream(writer, record.ActCat_3dig_code);
                WriteStringToStream(writer, record.ActCat_3dig_desc);
                WriteStringToStream(writer, record.LegalForm_code);
                WriteStringToStream(writer, record.LegalForm_desc);
                WriteStringToStream(writer, record.InstSectorCode_level1);
                WriteStringToStream(writer, record.InstSectorCode_level1_desc);
                WriteStringToStream(writer, record.InstSectorCode_level2);
                WriteStringToStream(writer, record.InstSectorCode_level2_desc);
                WriteNullableToStream(writer, record.SizeCode);
                WriteStringToStream(writer, record.SizeDesc);
                WriteNullableToStream(writer, record.Turnover);
                WriteNullableToStream(writer, record.Employees);
                WriteNullableToStream(writer, record.NumOfPeopleEmp);
                WriteNullableToStream(writer, record.RegistrationDate);
                WriteNullableToStream(writer, record.LiqDate);
                WriteStringToStream(writer, record.StatusCode);
                WriteStringToStream(writer, record.StatusDesc);
                WriteNullableToStream(writer, record.Sex, Environment.NewLine);
            }

            writer.Flush();
            return mem.ToArray();
        }
    }
}
