using System;
using System.Collections.Generic;
using System.Diagnostics;
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
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Common.Services.DataSources
{

    public class EditTracer
    {
        public Stopwatch liquidateStat = new Stopwatch();
        public int countliquidateStat;
        public Stopwatch noChanges = new Stopwatch();
        public int countnoChanges;
        public Stopwatch editStat = new Stopwatch();
        public int counteditStat;
        public Stopwatch elastic = new Stopwatch();
        public int countelastic;


    }

    public class EditUnitService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly CommonService _commonSvc;
        private readonly int? _liquidateStatusId;
        private readonly List<ElasticStatUnit> _editArrayStatisticalUnits;
        private readonly List<ElasticStatUnit> _addArrayStatisticalUnits;
        private readonly EditTracer _editTracer;
        private readonly string _userId;
        private readonly DataAccessPermissions _permissions;
        private readonly IMapper _mapper;

        public EditUnitService(NSCRegDbContext dbContext, /*CommonService commonSvc,*/ string userId, DataAccessPermissions permissions, IMapper mapper)
        {
            _permissions = permissions;
            _userId = userId;
            _dbContext = dbContext;
            _mapper = mapper;
            _commonSvc = new CommonService(dbContext, mapper);
            _liquidateStatusId = _dbContext.UnitStatuses.FirstOrDefault(x => x.Code == "7")?.Id;
            _editArrayStatisticalUnits = new List<ElasticStatUnit>();
            _addArrayStatisticalUnits = new List<ElasticStatUnit>();
            _editTracer = new EditTracer();            
        }

        /// <summary>
        /// Edit local unit method
        /// </summary>
        /// <param name="changedUnit"></param>
        /// <param name="historyUnit"></param>
        /// <returns> </returns>
        public async Task EditLocalUnit(LocalUnit changedUnit, LocalUnit historyUnit)
        {
            _editTracer.liquidateStat.Start();
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
                var legalUnit = await _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefaultAsync(x => changedUnit.LegalUnitId == x.RegId && !x.IsDeleted);
                if (legalUnit != null && legalUnit.LocalUnits.Any(x => !x.IsDeleted && x.UnitStatusId != _liquidateStatusId.Value))
                {
                    throw new BadRequestException(nameof(Resource.LiquidateLegalUnit));
                }
            }
            _editTracer.liquidateStat.Stop();
            Debug.WriteLine($"Liquidate legal {_editTracer.liquidateStat.ElapsedMilliseconds / ++_editTracer.countliquidateStat}");

            _editTracer.noChanges.Start();
            if (IsNoChanges(changedUnit, historyUnit)) return;
            _editTracer.noChanges.Stop();
            Debug.WriteLine($"No changes legal {_editTracer.liquidateStat.ElapsedMilliseconds / ++_editTracer.countliquidateStat}");

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                    var changedDateTime = DateTime.Now;
                    _commonSvc.AddHistoryUnitByType(CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));

                    _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                        changedDateTime, unitsHistoryHolder);

                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                    // TODO: Check
                    //if (_addArrayStatisticalUnits.Any())
                    //    foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                    //    {
                    //        await _elasticService.AddDocument(addArrayStatisticalUnit);
                    //    }
                    //if (_editArrayStatisticalUnits.Any())
                    //    foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                    //    {
                    //        await _elasticService.EditDocument(editArrayStatisticalUnit);
                    //    }

                    // await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(changedUnit));
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
        /// Edit legal unit method
        /// </summary>
        /// <param name="changedUnit"></param>
        /// <param name="historyUnit"></param>
        /// <returns></returns>
        public async Task EditLegalUnit(LegalUnit changedUnit, LegalUnit historyUnit)
        {
            _editTracer.liquidateStat.Start();
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
                    _editArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit));
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
                            _addArrayStatisticalUnits.Add(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
                        }
                        changedUnit.HistoryLocalUnitIds = string.Join(",", changedUnit.LocalUnits);
                    }
                }
                
            }
            _editTracer.liquidateStat.Stop();
            Debug.WriteLine($"Liquidate legal {_editTracer.liquidateStat.ElapsedMilliseconds / ++_editTracer.countliquidateStat}");

            _editTracer.noChanges.Start();
            if (IsNoChanges(changedUnit, historyUnit)) return;
            _editTracer.noChanges.Stop();
            Debug.WriteLine($"No changes legal {_editTracer.noChanges.ElapsedMilliseconds / ++_editTracer.countnoChanges}");

            changedUnit.UserId = _userId;
            changedUnit.ChangeReason = ChangeReasons.Edit;
            changedUnit.EditComment = "Changed by import service.";

            try
            {
                _editTracer.editStat.Start();
                var mappedHistoryUnit = _commonSvc.MapUnitToHistoryUnit(historyUnit);
                var changedDateTime = DateTime.Now;
                _dbContext.Update(changedUnit);
                _commonSvc.AddHistoryUnitByType(StatUnit.CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));
                _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                    changedDateTime, unitsHistoryHolder);
                if (deleteEnterprise)
                {
                    _dbContext.EnterpriseUnits.Remove(_dbContext.EnterpriseUnits.First(eu => eu.RegId == existingLeuEntRegId));
                }

                await _dbContext.SaveChangesAsync();
                _editTracer.editStat.Stop();
                Debug.WriteLine($"Edit legal {_editTracer.editStat.ElapsedMilliseconds / ++_editTracer.counteditStat}");

                _editTracer.elastic.Start();
                // TODO: CHeck
                //if (_addArrayStatisticalUnits.Any())
                //    foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                //    {
                //        await _elasticService.AddDocument(addArrayStatisticalUnit);
                //    }
                //if (_editArrayStatisticalUnits.Any())
                //    foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                //    {
                //        await _elasticService.EditDocument(editArrayStatisticalUnit);
                //    }

                //await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(changedUnit));
                _editTracer.elastic.Stop();
                Debug.WriteLine($"Elastic legal {_editTracer.elastic.ElapsedMilliseconds / ++_editTracer.countelastic}");
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

            //if (StatUnit.Common.HasAccess<EnterpriseUnit>(_permissions, v => v.LegalUnits))
            //{
            //    if (changedUnit.LegalUnits != null && changedUnit.LegalUnits.Any())
            //    {
            //        var legalUnits = _dbContext.LegalUnits.Where(x => changedUnit.LegalUnits.Contains(x));
            //        changedUnit.LegalUnits.Clear();
            //        changedUnit.HistoryLegalUnitIds = null;
            //        foreach (var legalUnit in legalUnits)
            //        {
            //            changedUnit.LegalUnits.Add(legalUnit);
            //            _addArrayStatisticalUnits.Add(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(legalUnit));
            //        }

            //        changedUnit.HistoryLegalUnitIds = string.Join(",", changedUnit.LegalUnits);
            //    }

            //}
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
                    _commonSvc.AddHistoryUnitByType(StatUnit.CommonService.TrackHistory(changedUnit, mappedHistoryUnit, changedDateTime));

                    _commonSvc.TrackRelatedUnitsHistory(changedUnit, historyUnit, _userId, changedUnit.ChangeReason, changedUnit.EditComment,
                        changedDateTime, unitsHistoryHolder);
                    
                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                    // TODO: check
                    //if (_addArrayStatisticalUnits.Any())
                    //    foreach (var addArrayStatisticalUnit in _addArrayStatisticalUnits)
                    //    {
                    //        await _elasticService.AddDocument(addArrayStatisticalUnit);
                    //    }
                    //if (_editArrayStatisticalUnits.Any())
                    //    foreach (var editArrayStatisticalUnit in _editArrayStatisticalUnits)
                    //    {
                    //        await _elasticService.EditDocument(editArrayStatisticalUnit);
                    //    }

                    //await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(changedUnit));
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
                var unitProperty = unitType.GetProperty(property.Name)?.GetValue(unit, null);
                var hUnitProperty = unitType.GetProperty(property.Name)?.GetValue(hUnit, null);
                if (!Equals(unitProperty, hUnitProperty)) return false;
            }
            if (!(unit is StatisticalUnit statUnit)) return true;
            var historyStatUnit = (StatisticalUnit)hUnit;
            return historyStatUnit.ActivitiesUnits.CompareWith(statUnit.ActivitiesUnits, v => v.ActivityId)
                   && historyStatUnit.PersonsUnits.CompareWith(statUnit.PersonsUnits, p => p.PersonId);
        }
    }
}
