using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class BulkUpsertUnitService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UpsertUnitBulkBuffer _bufferService;
        private readonly CommonService _commonSvc;
        private readonly int? _liquidateStatusId;
        private readonly string _userId;
        private readonly DataAccessPermissions _permissions;
        private readonly IMapper _mapper;

        public BulkUpsertUnitService(NSCRegDbContext context, UpsertUnitBulkBuffer buffer, DataAccessPermissions permissions, IMapper mapper, string userId)
        {
            _bufferService = buffer;
            _dbContext = context;
            _permissions = permissions;
            _userId = userId;
            _commonSvc = new CommonService(context, mapper);
            _liquidateStatusId = _dbContext.UnitStatuses.FirstOrDefault(x => x.Code == "7")?.Id;
            _mapper = mapper;
        }

        /// <summary>
        /// Creation of a local unit together with a legal unit, if there is none
        /// </summary>
        /// <param name="localUnit"></param>
        /// <returns></returns>
        public async Task CreateLocalUnit(LocalUnit localUnit)
        {
            try
            {
                await _bufferService.AddToBufferAsync(localUnit);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Creating a legal unit with a local unit and an enterprise
        /// </summary>
        /// <param name="legal"></param>
        /// <returns></returns>
        public async Task CreateLegalWithEnterpriseAndLocal(LegalUnit legal)
        {
            _bufferService.DisableFlushing();
            try
            {
                if (legal.EnterpriseUnitRegId == null || legal.EnterpriseUnitRegId == 0)
                {
                    var sameStatIdEnterprise =
                        await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(eu => eu.StatId == legal.StatId);

                    if (sameStatIdEnterprise != null)
                    {
                        legal.EnterpriseUnit = sameStatIdEnterprise;
                    }
                    else
                    {
                        CreateEnterpriseForLegal(legal);
                    }

                    await _bufferService.AddToBufferAsync(legal.EnterpriseUnit);

                }

                var addressIds = legal.LocalUnits.Where(x => x.ActualAddressId != null).Select(x => x.ActualAddressId).ToList();
                var addresses = await _dbContext.Address.Where(x => legal.ActualAddress != null &&
                    addressIds.Contains(x.Id) && x.RegionId == legal.ActualAddress.RegionId &&
                    x.AddressPart1 == legal.ActualAddress.AddressPart1 &&
                    x.AddressPart2 == legal.ActualAddress.AddressPart2 &&
                    x.AddressPart3 == legal.ActualAddress.AddressPart3 &&
                    x.Latitude == legal.ActualAddress.Latitude &&
                    x.Longitude == legal.ActualAddress.Longitude).ToListAsync();

                if (!addresses.Any())
                {
                    CreateLocalForLegal(legal);
                    await _bufferService.AddToBufferAsync(legal.LocalUnits.Last());
                }

                _bufferService.EnableFlushing();
                await _bufferService.AddToBufferAsync(legal);


            }
            catch (Exception e)
            {
                _bufferService.EnableFlushing();
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Creating an enterprise with a group of enterprises
        /// </summary>
        /// <param name = "enterpriseUnit" ></param >
        /// < returns ></returns >
        public async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            try
            {
                if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId <= 0)
                {
                    CreateGroupForEnterprise(enterpriseUnit);
                }
                await _bufferService.AddToBufferAsync(enterpriseUnit);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Edit legal unit method
        /// </summary>
        /// <param name="changedUnit"></param>
        /// <param name="historyUnit"></param>
        /// <returns></returns>
        public async Task EditLegalUnit(LegalUnit changedUnit, LegalUnit historyUnit)
        {
            var unitsHistoryHolder = new UnitsHistoryHolder(changedUnit);
            var deleteEnterprise = false;
            var existingLeuEntRegId = await _dbContext.LegalUnits.Where(leu => leu.RegId == changedUnit.RegId)
                .Select(leu => leu.EnterpriseUnitRegId).FirstOrDefaultAsync();
            if (existingLeuEntRegId != changedUnit.EnterpriseUnitRegId &&
                !_dbContext.LegalUnits.Any(leu => leu.EnterpriseUnitRegId == existingLeuEntRegId))
                deleteEnterprise = true;


            if (_liquidateStatusId != null && historyUnit.UnitStatusId == _liquidateStatusId && changedUnit.UnitStatusId != historyUnit.UnitStatusId)
            {
                throw new BadRequestException(nameof(Resource.UnitHasLiquidated));
            }

            if (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId)
            {
                var enterpriseUnit = await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(x => changedUnit.EnterpriseUnitRegId == x.RegId);

                var legalUnitsAnyNotLiquidated = await _dbContext.LegalUnits.AnyAsync(x => x.EnterpriseUnitRegId == enterpriseUnit.RegId && !x.IsDeleted && x.UnitStatusId != _liquidateStatusId);

                if (enterpriseUnit != null && !legalUnitsAnyNotLiquidated)
                {
                    enterpriseUnit.UnitStatusId = changedUnit.UnitStatusId;
                    enterpriseUnit.LiqReason = changedUnit.LiqReason;
                    enterpriseUnit.LiqDate = changedUnit.LiqDate;
                    await _bufferService.AddToBufferAsync(enterpriseUnit);
                }
                if (CommonService.HasAccess<LegalUnit>(_permissions, v => v.LocalUnits))
                {
                    if (changedUnit.LocalUnits != null && changedUnit.LocalUnits.Any())
                    {
                        foreach (var localUnit in changedUnit.LocalUnits.Where(x => x.UnitStatusId != _liquidateStatusId))
                        {
                            localUnit.UnitStatusId = changedUnit.UnitStatusId;
                            localUnit.LiqReason = changedUnit.LiqReason;
                            localUnit.LiqDate = changedUnit.LiqDate;
                            await _bufferService.AddToBufferAsync(localUnit);
                        }
                        changedUnit.HistoryLocalUnitIds = string.Join(",", changedUnit.LocalUnits.Select(x => x.RegId));
                    }
                }

            }
            if (IsNoChanges(changedUnit, historyUnit)) return;

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            try
            {
                var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                var changedDateTime = DateTime.Now;
                await _bufferService.AddToBufferAsync(changedUnit);

                var hUnit = CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime);
                _commonSvc.AddHistoryUnitByType(hUnit);
                _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                    changedDateTime, unitsHistoryHolder);
                if (deleteEnterprise)
                {
                    var enterpriseUnit = _dbContext.EnterpriseUnits.First(eu => eu.RegId == existingLeuEntRegId);
                    _bufferService.AddToDeleteBuffer(enterpriseUnit);
                }
            }
            catch (NotFoundException e)
            {
                throw new BadRequestException(nameof(Resource.ElasticSearchIsDisable), e);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Edit local unit method
        /// </summary>
        /// <param name="changedUnit"></param>
        /// <param name="historyUnit"></param>
        /// <returns> </returns>
        public async Task EditLocalUnit(LocalUnit changedUnit, LocalUnit historyUnit)
        {
            var unitsHistoryHolder = new UnitsHistoryHolder(changedUnit);

            if (_liquidateStatusId != null && historyUnit.UnitStatusId == _liquidateStatusId && changedUnit.UnitStatusId != historyUnit.UnitStatusId)
            {
                throw new BadRequestException(nameof(Resource.UnitHasLiquidated));
            }

            if (changedUnit.LiqDate != null || !string.IsNullOrEmpty(changedUnit.LiqReason)
                || (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId))
            {
                changedUnit.UnitStatusId = _liquidateStatusId;
                changedUnit.LiqDate = changedUnit.LiqDate ?? DateTime.Now;
            }

            if ((historyUnit.LiqDate != null && changedUnit.LiqDate == null) || (!string.IsNullOrEmpty(historyUnit.LiqReason)
                && string.IsNullOrEmpty(changedUnit.LiqReason)))
            {
                changedUnit.LiqDate = changedUnit.LiqDate ?? historyUnit.LiqDate;
                changedUnit.LiqReason = string.IsNullOrEmpty(changedUnit.LiqReason) ? historyUnit.LiqReason : changedUnit.LiqReason;
            }

            if (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId)
            {
                var legalUnit = await _dbContext.LegalUnits.Include(x => x.LocalUnits)
                    .FirstOrDefaultAsync(x => changedUnit.LegalUnitId == x.RegId && !x.IsDeleted);
                if (legalUnit != null && legalUnit.LocalUnits.Any(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId.Value))
                {
                    throw new BadRequestException(nameof(Resource.LiquidateLegalUnit));
                }
            }

            if (IsNoChanges(changedUnit, historyUnit)) return;

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";
            try
            {
                var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                var changedDateTime = DateTime.Now;
                await _bufferService.AddToBufferAsync(changedUnit);

                _commonSvc.AddHistoryUnitByType(CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));
                _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                    changedDateTime, unitsHistoryHolder);
            }
            catch (NotFoundException e)
            {
                throw new BadRequestException(nameof(Resource.ElasticSearchIsDisable), e);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Edit enterprise unit method
        /// </summary>
        /// <param name="changedUnit"></param>
        /// <param name="historyUnit"></param>
        /// <returns> </returns>
        public async Task EditEnterpriseUnit(EnterpriseUnit changedUnit, EnterpriseUnit historyUnit)
        {
            var unitsHistoryHolder = new UnitsHistoryHolder(changedUnit);

            if (_liquidateStatusId != null && historyUnit.UnitStatusId == _liquidateStatusId && changedUnit.UnitStatusId != historyUnit.UnitStatusId)
            {
                throw new BadRequestException(nameof(Resource.UnitHasLiquidated));
            }

            if (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId)
            {
                throw new BadRequestException(nameof(Resource.LiquidateEntrUnit));
            }

            if (IsNoChanges(changedUnit, historyUnit)) return;

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            try
            {
                var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                var changedDateTime = DateTime.Now;

                await _bufferService.AddToBufferAsync(changedUnit);

                _commonSvc.AddHistoryUnitByType(CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));
                _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                    changedDateTime, unitsHistoryHolder);
            }
            catch (NotFoundException e)
            {
                throw new BadRequestException(nameof(Resource.ElasticSearchIsDisable), e);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }

        /// <summary>
        /// Method for checking for data immutability
        /// </summary>
        /// <param name = "unit"> Stat. units </param>
        /// <param name = "hUnit"> History of stat. units </param>
        /// <returns> </returns>
        private static bool IsNoChanges(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var unitType = unit.GetType();
            var propertyInfo = unitType.GetProperties();
            foreach (var property in propertyInfo)
            {
                var unitProperty = unitType.GetProperty(property.Name)?.GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name)?.GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            if (!(unit is StatisticalUnit statUnit)) return true;
            var historyStatUnit = (StatisticalUnit)hUnit;
            return historyStatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId)
                && historyStatUnit.PersonsUnits.CompareWith(statUnit.PersonsUnits, p => p.PersonId);
        }

        private void CreateEnterpriseForLegal(LegalUnit legalUnit)
        {
            var enterpriseUnit = new EnterpriseUnit();
            _mapper.Map(legalUnit, enterpriseUnit);
            enterpriseUnit.ActualAddress = legalUnit.ActualAddress;
            enterpriseUnit.PostalAddress = legalUnit.PostalAddress;
            enterpriseUnit.StartPeriod = legalUnit.StartPeriod;
            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits,
                legalUnit.ForeignParticipationCountriesUnits, enterpriseUnit);
            legalUnit.EnterpriseUnit = enterpriseUnit;
        }
        private void CreateLocalForLegal(LegalUnit legalUnit)
        {
            var localUnit = new LocalUnit();
            _mapper.Map(legalUnit, localUnit);
            localUnit.ActualAddress = legalUnit.ActualAddress;
            localUnit.PostalAddress = legalUnit.PostalAddress;
            localUnit.LegalUnit = legalUnit;
            localUnit.StartPeriod = legalUnit.StartPeriod;
            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits,
                legalUnit.ForeignParticipationCountriesUnits, localUnit);
            legalUnit.LocalUnits.Add(localUnit);
        }
        private void CreateGroupForEnterprise(EnterpriseUnit enterpriseUnit)
        {
            var enterpriseGroup = new EnterpriseGroup();
            _mapper.Map(enterpriseUnit, enterpriseGroup);
            enterpriseUnit.EnterpriseGroup = enterpriseGroup;
        }

        private void CreateActivitiesAndPersonsAndForeignParticipations(IEnumerable<Activity> activities,
            IEnumerable<PersonStatisticalUnit> persons, IEnumerable<CountryStatisticalUnit> foreignPartCountries, StatisticalUnit unit)
        {
            activities.ForEach(a => unit.ActivitiesUnits.Add(new ActivityStatisticalUnit
            {
                Activity = a
            }));
            persons.ForEach(x =>
            {
                unit.PersonsUnits.Add(new PersonStatisticalUnit
                {
                    PersonId = x.PersonId,
                    Person = x.Person,
                    PersonTypeId = x.PersonTypeId,
                    PersonType = x.PersonType,
                    EnterpriseGroupId = x.EnterpriseGroupId,
                    EnterpriseGroup = x.EnterpriseGroup
                });
            });

            foreignPartCountries.ForEach(x =>
            {
                unit.ForeignParticipationCountriesUnits.Add(new CountryStatisticalUnit
                {
                    CountryId = x.CountryId
                });
            });
        }
    }
}
