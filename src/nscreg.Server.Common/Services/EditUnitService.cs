using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Common.Validators.Extentions;
using nscreg.Utilities;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using Activity = nscreg.Data.Entities.Activity;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using Person = nscreg.Data.Entities.Person;

namespace nscreg.Server.Common.Services
{
    public class EditUnitService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly StatUnit.Common _commonSvc;
        private readonly ElasticService _elasticService;
        private readonly int? _liquidateStatusId;
        private readonly List<ElasticStatUnit> _editArrayStatisticalUnits;
        private readonly List<ElasticStatUnit> _addArrayStatisticalUnits;
        private readonly string _userId;

        public EditUnitService(NSCRegDbContext dbContext, string userId)
        {
            _userId = userId;
            _dbContext = dbContext;
            _commonSvc = new StatUnit.Common(dbContext);
            _elasticService = new ElasticService(dbContext);
            _liquidateStatusId = _dbContext.Statuses.FirstOrDefault(x => x.Code == "7")?.Id;
            _editArrayStatisticalUnits = new List<ElasticStatUnit>();
            _addArrayStatisticalUnits = new List<ElasticStatUnit>();
        }

        /// <summary>
        /// Method of editing a legal unit
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        //public async Task<Dictionary<string, string[]>> EditLegalUnit(LegalUnitEditM data, string userId)
        //    => await EditUnitContext<LegalUnit, LegalUnitEditM>(
        //        data,
        //        m => m.RegId ?? 0,
        //        userId, (unit) =>
        //        {
        //            if (!StatUnit.Common.HasAccess<LegalUnit>(data.DataAccess, v => v.LocalUnits))
        //            {
        //                return Task.CompletedTask;
        //            }
        //            if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
        //            {
        //                var enterpriseUnit = _dbContext.EnterpriseUnits.Include(x => x.LegalUnits).FirstOrDefault(x => unit.EnterpriseUnitRegId == x.RegId);
        //                var legalUnits = enterpriseUnit?.LegalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId).ToList();
        //                if (enterpriseUnit != null && legalUnits.Count == 0)
        //                {
        //                    enterpriseUnit.UnitStatusId = unit.UnitStatusId;
        //                    enterpriseUnit.LiqReason = unit.LiqReason;
        //                    enterpriseUnit.LiqDate = unit.LiqDate;
        //                    _editArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit));
        //                }
        //            }

        //            if (data.LocalUnits != null && data.LocalUnits.Any())
        //            {
        //                //TODO: Инклуд у базовой сущности
        //                var localUnits = _dbContext.LocalUnits.Where(x => data.LocalUnits.Contains(x.RegId) && x.UnitStatusId != _liquidateStatusId);

        //                unit.LocalUnits.Clear();
        //                unit.HistoryLocalUnitIds = null;
        //                foreach (var localUnit in localUnits)
        //                {
        //                    if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
        //                    {
        //                        localUnit.UnitStatusId = unit.UnitStatusId;
        //                        localUnit.LiqReason = unit.LiqReason;
        //                        localUnit.LiqDate = unit.LiqDate;
        //                    }
        //                    unit.LocalUnits.Add(localUnit);
        //                    _addArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
        //                }
        //                unit.HistoryLocalUnitIds = string.Join(",", data.LocalUnits);
        //            }
        //            return Task.CompletedTask;
        //        });

        /// <summary>
        /// Local unit editing method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        //public async Task<Dictionary<string, string[]>> EditLocalUnit(LocalUnitEditM data, string userId)
        //    => await EditUnitContext<LocalUnit, LocalUnitEditM>(
        //        data,
        //        v => v.RegId ?? 0,
        //        userId,
        //        unit =>
        //        {
        //            if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
        //            {
        //                var legalUnit = _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefault(x => unit.LegalUnitId == x.RegId && !x.IsDeleted);
        //                if (legalUnit != null && legalUnit.LocalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId.Value).ToList().Count == 0)
        //                {
        //                    throw new BadRequestException(nameof(Resource.LiquidateLegalUnit));
        //                }
        //            }
        //            return Task.CompletedTask;
        //        });

        /// <summary>
        /// Enterprise editing method
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        //public async Task<Dictionary<string, string[]>> EditEnterpriseUnit(EnterpriseUnitEditM data, string userId)
        //    => await EditUnitContext<EnterpriseUnit, EnterpriseUnitEditM>(
        //        data,
        //        m => m.RegId ?? 0,
        //        userId,
        //        unit =>
        //        {
        //            if (_liquidateStatusId != null && unit.UnitStatusId == _liquidateStatusId)
        //            {
        //                throw new BadRequestException(nameof(Resource.LiquidateEntrUnit));
        //            }
        //            if (StatUnit.Common.HasAccess<EnterpriseUnit>(data.DataAccess, v => v.LegalUnits))
        //            {
        //                if (data.LegalUnits != null && data.LegalUnits.Any())
        //                {
        //                    var legalUnits = _dbContext.LegalUnits.Where(x => data.LegalUnits.Contains(x.RegId));
        //                    unit.LegalUnits.Clear();
        //                    unit.HistoryLegalUnitIds = null;
        //                    foreach (var legalUnit in legalUnits)
        //                    {
        //                        unit.LegalUnits.Add(legalUnit);
        //                        _addArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(legalUnit));
        //                    }

        //                    unit.HistoryLegalUnitIds = string.Join(",", data.LegalUnits);
        //                }

        //            }
        //            return Task.CompletedTask;
        //        });

        /// <summary>
        /// Method of editing a group of enterprises
        /// </summary>
        /// <param name = "data"> Data </param>
        /// <param name = "userId"> User Id </param>
        /// <returns> </returns>
        //public async Task<Dictionary<string, string[]>> EditEnterpriseGroup(EnterpriseGroupEditM data, string userId)
        //    => await EditContext<EnterpriseGroup, EnterpriseGroupEditM>(
        //        data,
        //        m => m.RegId ?? 0,
        //        userId,
        //        (unit, oldUnit) =>
        //        {
        //            if (StatUnit.Common.HasAccess<EnterpriseGroup>(data.DataAccess, v => v.EnterpriseUnits))
        //            {
        //                if (data.EnterpriseUnits != null && data.EnterpriseUnits.Any())
        //                {
        //                    var enterprises = _dbContext.EnterpriseUnits.Where(x => data.EnterpriseUnits.Contains(x.RegId));
        //                    unit.EnterpriseUnits.Clear();
        //                    unit.HistoryEnterpriseUnitIds = null;
        //                    foreach (var enterprise in enterprises)
        //                    {
        //                        unit.EnterpriseUnits.Add(enterprise);
        //                        _addArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterprise));
        //                    }
        //                    unit.HistoryEnterpriseUnitIds = string.Join(",", data.EnterpriseUnits);
        //                }
        //            }

        //            return Task.CompletedTask;
        //        });

        /// <summary>
        /// Context editing method
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

            if (changedUnit.LiqDate != null || !string.IsNullOrEmpty(changedUnit.LiqReason) || (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId))
            {
                changedUnit.UnitStatusId = _liquidateStatusId;
                changedUnit.LiqDate = changedUnit.LiqDate ?? DateTime.Now;
            }

            if ((historyUnit.LiqDate != null && changedUnit.LiqDate == null) || (!string.IsNullOrEmpty(historyUnit.LiqReason) && string.IsNullOrEmpty(changedUnit.LiqReason)))
            {
                changedUnit.LiqDate = changedUnit.LiqDate ?? historyUnit.LiqDate;
                changedUnit.LiqReason = string.IsNullOrEmpty(changedUnit.LiqReason) ? historyUnit.LiqReason : changedUnit.LiqReason;
            }

            if (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId)
            {
                var legalUnit = await  _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefaultAsync(x => changedUnit.LegalUnitId == x.RegId && !x.IsDeleted);
                if (legalUnit != null && legalUnit.LocalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId.Value).ToList().Count == 0)
                {
                    throw new BadRequestException(nameof(Resource.LiquidateLegalUnit));
                }
            }
            if (IsNoChanges(changedUnit, historyUnit)) return;

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                    var changedDateTime = DateTime.Now;
                    _commonSvc.AddHistoryUnitByType(StatUnit.Common.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));

                    _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                        changedDateTime, unitsHistoryHolder);

                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                    if (_addArrayStatisticalUnits.Any())
                        foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                        {
                            await _elasticService.AddDocument(addArrayStatisticalUnit);
                        }
                    if (_editArrayStatisticalUnits.Any())
                        foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                        {
                            await _elasticService.EditDocument(editArrayStatisticalUnit);
                        }

                    await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(changedUnit));
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
        }
        public async Task EditLegalUnit(LegalUnit changedUnit, LegalUnit historyUnit)
        {
            var unitsHistoryHolder = new UnitsHistoryHolder(changedUnit);


            var deleteEnterprise = false;
            var existingLeuEntRegId = _dbContext.LegalUnits.Where(leu => leu.RegId == changedUnit.RegId)
                .Select(leu => leu.EnterpriseUnitRegId).FirstOrDefault();
            if (existingLeuEntRegId != changedUnit.EnterpriseUnitRegId &&
                !_dbContext.LegalUnits.Any(leu => leu.EnterpriseUnitRegId == existingLeuEntRegId))
                deleteEnterprise = true;

            if (_liquidateStatusId != null && historyUnit.UnitStatusId == _liquidateStatusId && changedUnit.UnitStatusId != historyUnit.UnitStatusId)
            {
                throw new BadRequestException(nameof(Resource.UnitHasLiquidated));
            }

            if (_liquidateStatusId != null && changedUnit.UnitStatusId == _liquidateStatusId)
            {
                var enterpriseUnit = _dbContext.EnterpriseUnits.Include(x => x.LegalUnits).FirstOrDefault(x => changedUnit.EnterpriseUnitRegId == x.RegId);
                var legalUnits = enterpriseUnit?.LegalUnits.Where(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId).ToList();
                if (enterpriseUnit != null && !legalUnits.Any())
                {
                    enterpriseUnit.UnitStatusId = changedUnit.UnitStatusId;
                    enterpriseUnit.LiqReason = changedUnit.LiqReason;
                    enterpriseUnit.LiqDate = changedUnit.LiqDate;
                    _editArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit));
                }
                if (changedUnit.LocalUnits != null && changedUnit.LocalUnits.Any())
                {
                    foreach (var localUnit in changedUnit.LocalUnits.Where(x => x.UnitStatusId != _liquidateStatusId))
                    {
                        localUnit.UnitStatusId = changedUnit.UnitStatusId;
                        localUnit.LiqReason = changedUnit.LiqReason;
                        localUnit.LiqDate = changedUnit.LiqDate;
                        _addArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
                    }
                    changedUnit.HistoryLocalUnitIds = string.Join(",", changedUnit.LocalUnits);
                }
            }
            if (IsNoChanges(changedUnit, historyUnit)) return;

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                    var changedDateTime = DateTime.Now;
                    _commonSvc.AddHistoryUnitByType(StatUnit.Common.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));

                    _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                        changedDateTime, unitsHistoryHolder);


                    if (deleteEnterprise)
                    {
                        _dbContext.EnterpriseUnits.Remove(_dbContext.EnterpriseUnits.First(eu => eu.RegId == existingLeuEntRegId));
                    }

                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                    await _elasticService.CheckElasticSearchConnection();
                    if (_addArrayStatisticalUnits.Any())
                        foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                        {
                            await _elasticService.AddDocument(addArrayStatisticalUnit);
                        }
                    if (_editArrayStatisticalUnits.Any())
                        foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                        {
                            await _elasticService.EditDocument(editArrayStatisticalUnit);
                        }

                    await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(changedUnit));
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
                var unitProperty = unitType.GetProperty(property.Name).GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name).GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            if (!(unit is StatisticalUnit statUnit)) return true;
            var hstatUnit = (StatisticalUnit)hUnit;
            return hstatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId)
                   && hstatUnit.PersonsUnits.CompareWith(statUnit.PersonsUnits, p => p.PersonId);
        }
    }
}
