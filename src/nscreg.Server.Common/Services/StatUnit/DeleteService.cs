using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using EFCore.BulkExtensions;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.History;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Utilities.Enums;
using nscreg.Utilities.Extensions;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Class Service Removal
    /// </summary>
    public class DeleteService
    {
        private readonly Common _commonSvc;
        private readonly UserService _userService;
        private readonly Dictionary<StatUnitTypes, Func<int, bool, string, IStatisticalUnit>> _deleteUndeleteActions;
        private readonly Dictionary<StatUnitTypes, Action<IStatisticalUnit, bool, string>> _postDeleteActions;
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticService _elasticService;
        private readonly DataAccessService _dataAccessService;

        public DeleteService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _elasticService = new ElasticService(dbContext);
            _dataAccessService = new DataAccessService(dbContext);
            _commonSvc = new Common(dbContext);
            _userService = new UserService(dbContext);
            _deleteUndeleteActions = new Dictionary<StatUnitTypes, Func<int, bool, string, IStatisticalUnit>>
            {
                [StatUnitTypes.EnterpriseGroup] = DeleteUndeleteEnterpriseGroupUnit,
                [StatUnitTypes.EnterpriseUnit] = DeleteUndeleteEnterpriseUnit,
                [StatUnitTypes.LocalUnit] = DeleteUndeleteLocalUnit,
                [StatUnitTypes.LegalUnit] = DeleteUndeleteLegalUnit
            };
            _postDeleteActions = new Dictionary<StatUnitTypes, Action<IStatisticalUnit, bool, string>>
            {
                [StatUnitTypes.EnterpriseGroup] = PostDeleteEnterpriseGroupUnit,
                [StatUnitTypes.EnterpriseUnit] = PostDeleteEnterpriseUnit,
                [StatUnitTypes.LocalUnit] = PostDeleteLocalUnit,
                [StatUnitTypes.LegalUnit] = PostDeleteLegalUnit
            };
        }

        /// <summary>
        /// Delete / Restore stat. units
        /// </summary>
        /// <param name="unitType">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <param name="toDelete">Remoteness flag</param>
        /// <param name="userId">User ID</param>
        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete, string userId)
        {
            if (_dataAccessService.CheckWritePermissions(userId, unitType))
            {
                throw new UnauthorizedAccessException();
            }

            var item = _commonSvc.GetStatisticalUnitByIdAndType(id, unitType, true).Result;
            bool isEmployee = _userService.IsInRoleAsync(userId, DefaultRoleNames.Employee).Result;
            var mappedItem = Mapper.Map<IStatisticalUnit, ElasticStatUnit>(item);
            if (isEmployee)
            {
                var helper = new StatUnitCheckPermissionsHelper(_dbContext);
                helper.CheckRegionOrActivityContains(userId, mappedItem.RegionIds, mappedItem.ActivityCategoryIds);
            }
            if (item.IsDeleted == toDelete)
            {
                _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(item)).Wait();
            }
            else
            {
                CheckBeforeDelete(item, toDelete);
                var deletedUnit = _deleteUndeleteActions[unitType](id, toDelete, userId);
                _postDeleteActions[unitType](deletedUnit, toDelete, userId);

                _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(deletedUnit)).Wait();
            }
        }

        /// <summary>
        /// Deleting / Restoring an Enterprise Group
        /// </summary>
        /// <param name="id">Id stat. units</param>
        /// <param name="toDelete">Remoteness flag</param>
        /// <param name="userId">User ID</param>
        private IStatisticalUnit DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new EnterpriseGroupHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            if (!toDelete)
                unit.UnitStatusId = _dbContext.EnterpriseGroupHistory.Where(x => x.ParentId == unit.RegId).OrderBy(x => x.StartPeriod).LastOrDefault()?.UnitStatusId;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseGroupHistory.Add((EnterpriseGroupHistory)Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        /// Deleting / Restoring a Legal Unit
        /// </summary>
        /// <param name="id">Id stat. units</param>
        /// <param name="toDelete">Remoteness flag</param>
        /// <param name="userId">User ID</param>
        private IStatisticalUnit DeleteUndeleteLegalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new LegalUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            if (!toDelete)
                unit.UnitStatusId = _dbContext.LegalUnitHistory.Where(x => x.ParentId == unit.RegId).OrderBy(x => x.StartPeriod).LastOrDefault()?.UnitStatusId;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LegalUnitHistory.Add((LegalUnitHistory)Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        /// Delete / Restore Local Unit
        /// </summary>
        /// <param name="id">Id stat. units</param>
        /// <param name="toDelete">Remoteness flag</param>
        /// <param name="userId">User ID</param>
        private IStatisticalUnit DeleteUndeleteLocalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new LocalUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            if (!toDelete)
                unit.UnitStatusId = _dbContext.LocalUnitHistory.Where(x => x.ParentId == unit.RegId).OrderBy(x => x.StartPeriod).LastOrDefault()?.UnitStatusId;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LocalUnitHistory.Add((LocalUnitHistory)Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        ///Enterprise Deletion / Restoration
        /// </summary>
        /// <param name="id">Id stat. units</param>
        /// <param name="toDelete">Remoteness flag</param>
        /// <param name="userId">User ID</param>
        private IStatisticalUnit DeleteUndeleteEnterpriseUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new EnterpriseUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            if (!toDelete)
                unit.UnitStatusId = _dbContext.EnterpriseUnitHistory.Where(x => x.ParentId == unit.RegId).OrderBy(x => x.StartPeriod).LastOrDefault()?.UnitStatusId;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseUnitHistory.Add((EnterpriseUnitHistory)Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        public void CheckBeforeDelete(IStatisticalUnit unit, bool toDelete)
        {
            if (toDelete)
            {
                switch (unit.GetType().Name)
                {
                    case nameof(LocalUnit):
                        {
                            var localUnit = unit as LocalUnit;
                            var legalUnit = _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefault(x => localUnit.LegalUnitId == x.RegId && !x.IsDeleted);
                            if (legalUnit != null && legalUnit.LocalUnits.Count == 1)
                            {
                                throw new BadRequestException(nameof(Resource.DeleteLocalUnit));
                            }
                            break;
                        }
                    case nameof(EnterpriseUnit):
                        {
                            var entUnit = unit as EnterpriseUnit;
                            if (entUnit != null && entUnit.LegalUnits.Any(c => !c.IsDeleted))
                            {
                                throw new BadRequestException(nameof(Resource.DeleteEnterpriseUnit));
                            }
                            break;
                        }
                }
            }
            else
            {
                switch (unit.GetType().Name)
                {
                    case nameof(LocalUnit):
                        {
                            var localUnit = unit as LocalUnit;
                            var legalUnit = _dbContext.LegalUnits.Include(x => x.LocalUnits).FirstOrDefault(x => localUnit.LegalUnitId == x.RegId);
                            if (legalUnit != null && legalUnit.IsDeleted)
                            {
                                throw new BadRequestException(nameof(Resource.RestoreLocalUnit));
                            }
                            break;
                        }
                    case nameof(EnterpriseUnit):
                        {
                            var entUnit = unit as EnterpriseUnit;
                            if (entUnit != null && entUnit.LegalUnits.Any(x => x.IsDeleted))
                            {
                                throw new BadRequestException(nameof(Resource.RestoreEnterpriseUnit));
                            }
                            break;
                        }
                }
            }
        }

        public void StatUnitPostDeleteActions(IStatisticalUnit unit, bool toDelete, string userId)
        {
            _postDeleteActions[unit.UnitType](unit, toDelete, userId);
        }

        private void PostDeleteLocalUnit(IStatisticalUnit unit, bool toDelete, string userId)
        {
        }

        private void PostDeleteLegalUnit(IStatisticalUnit unit, bool toDelete, string userId)
        {
            var legalUnit = unit as LegalUnit;
            if (toDelete)
            {
                var legalStartPeriod = _dbContext.LegalUnitHistory.Where(x => x.ParentId == legalUnit.RegId).OrderBy(x => x.StartPeriod).FirstOrDefault()?.StartPeriod;
                foreach (var localUnit in legalUnit.LocalUnits)
                {
                    var localStartPeriod = _dbContext.LocalUnitHistory.Where(x => x.ParentId == localUnit.RegId).OrderBy(x => x.StartPeriod).FirstOrDefault()?.StartPeriod;
                    if (localStartPeriod == null) localStartPeriod = localUnit.StartPeriod;
                    if (localStartPeriod == legalStartPeriod)
                    {
                        var deletedUnit = DeleteUndeleteLocalUnit(localUnit.RegId, true, userId);
                        _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(deletedUnit)).Wait();
                    }
                }

                var enterpriseUnit = _dbContext.EnterpriseUnits.Include(x => x.LegalUnits).FirstOrDefault(x => x.RegId == legalUnit.EnterpriseUnitRegId);
                if (enterpriseUnit.LegalUnits.Count == 1)
                {
                    var deletedUnit = DeleteUndeleteEnterpriseUnit(enterpriseUnit.RegId, true, userId);
                    _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(deletedUnit)).Wait();
                }
            }
            else
            {
                var deletedLocalUnits = legalUnit.LocalUnits.Where(x => x.IsDeleted == true);
                foreach (var localUnit in deletedLocalUnits)
                {
                    var restoredUnit = DeleteUndeleteLocalUnit(localUnit.RegId, false, userId);
                    _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(restoredUnit)).Wait();
                }
                var enterpriseUnit = _dbContext.EnterpriseUnits.FirstOrDefault(x => x.RegId == legalUnit.EnterpriseUnitRegId);
                if (enterpriseUnit != null && enterpriseUnit.IsDeleted == true)
                {
                    var restoredUnit = DeleteUndeleteEnterpriseUnit(legalUnit.EnterpriseUnit.RegId, false, userId);
                    _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(restoredUnit)).Wait();
                }
            }
        }

        private void PostDeleteEnterpriseUnit(IStatisticalUnit unit, bool toDelete, string userId)
        {
        }

        private void PostDeleteEnterpriseGroupUnit(IStatisticalUnit unit, bool toDelete, string userId)
        {

        }

        /// <summary>
        /// Updates unit to the state before data source upload, reject data source queue/log case
        /// </summary>
        /// <param name="unit">Unit</param>
        /// <param name="historyUnit">History unit</param>
        /// <param name="userId">Id of user that rejectes data source queue</param>
        /// <param name="type">Type of statistical unit</param>
        public async Task UpdateUnitTask(dynamic unit, dynamic historyUnit, string userId, StatUnitTypes type)
        {
            var unitForUpdate = type == StatUnitTypes.LegalUnit
                ? Mapper.Map<LegalUnit>(unit)
                : (type == StatUnitTypes.LocalUnit
                    ? Mapper.Map<LocalUnit>(unit)
                    : Mapper.Map<EnterpriseUnit>(unit));

            Mapper.Map(historyUnit, unitForUpdate);
            unitForUpdate.EndPeriod = unit.EndPeriod;
            unitForUpdate.EditComment =
                "This unit was edited by data source upload service and then data upload changes rejected";
            unitForUpdate.RegId = unit.RegId;
            unitForUpdate.UserId = userId;
            unitForUpdate.ActivitiesUnits.Clear();
            unitForUpdate.PersonsUnits.Clear();
            unitForUpdate.ForeignParticipationCountriesUnits.Clear();
            foreach (var historyActUnit in historyUnit.ActivitiesUnits)
            {
                unitForUpdate.ActivitiesUnits.Add(Mapper.Map(historyActUnit, new ActivityStatisticalUnit()));
            }
            foreach (var historyPersonUnit in historyUnit.PersonsUnits)
            {
                unitForUpdate.PersonsUnits.Add(Mapper.Map(historyPersonUnit, new PersonStatisticalUnit()));
            }
            foreach (var historyCountryUnit in historyUnit.ForeignParticipationCountriesUnits)
            {
                unitForUpdate.ForeignParticipationCountriesUnits.Add(Mapper.Map(historyCountryUnit, new CountryStatisticalUnit()));
            }
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    _dbContext.LegalUnits.Update(unitForUpdate);
                    break;
                case StatUnitTypes.LocalUnit:
                    _dbContext.LocalUnits.Update(unitForUpdate);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    _dbContext.EnterpriseUnits.Update(unitForUpdate);
                    break;
            }
            await _dbContext.SaveChangesAsync();
            await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unitForUpdate));
        }

        /// <summary>
        /// Delete legal unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="userId">Id of user for edit unit if there is history</param>
        /// <param name="dataUploadTime">data source upload time</param>
        public async Task<bool> DeleteLegalUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.LegalUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .FirstOrDefault(legU => legU.StatId == statId);

            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return false;

            var afterUploadLegalUnitsList = _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod >= dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();

            var beforeUploadLegalUnitsList = _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod < dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();

            if (afterUploadLegalUnitsList.Any()) return false;

            if (beforeUploadLegalUnitsList.Any())
            {
                await UpdateUnitTask(unit, beforeUploadLegalUnitsList.Last(), userId, StatUnitTypes.LegalUnit);
                _dbContext.LegalUnitHistory.Remove(beforeUploadLegalUnitsList.Last());
                await _dbContext.SaveChangesAsync();
            }
            else
            {
                var localUnitDeleted = await DeleteLocalUnitFromDb(statId, userId, dataUploadTime);
                LocalUnit local = null;
                if (!localUnitDeleted)
                {
                    local = await _dbContext.LocalUnits.FirstOrDefaultAsync(x => x.LegalUnitId == unit.RegId);
                    if (local != null)
                    {
                        local.LegalFormId = null;
                    }
                }

                _dbContext.LegalUnits.Remove(unit);
                await _dbContext.SaveChangesAsync();
                await _elasticService.DeleteDocumentAsync(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit));

                if (local != null)
                {
                    await _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(local));
                    _commonSvc.TrackUnitHistoryFor<LocalUnit>(local.RegId, userId, ChangeReasons.Edit, "Link to Legal Unit deleted by data source upload service reject functionality", DateTime.Now);
                }

                await DeleteEnterpriseUnitFromDb(statId, userId, dataUploadTime);
            }

            return true;
        }

        /// <summary>
        /// Delete local unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task<bool> DeleteLocalUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.LocalUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .FirstOrDefault(local => local.StatId == statId && local.StartPeriod >= dataUploadTime);

            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId))
                return false;

            var afterUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod >= dataUploadTime).OrderBy(local => local.StartPeriod).ToList();

            var beforeUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod < dataUploadTime).OrderBy(local => local.StartPeriod).ToList();

            if (afterUploadLocalUnitsList.Any())
                return false;

            if (beforeUploadLocalUnitsList.Any())
            {
                await UpdateUnitTask(unit, beforeUploadLocalUnitsList.Last(), userId, StatUnitTypes.LocalUnit);
                _dbContext.LocalUnitHistory.Remove(beforeUploadLocalUnitsList.Last());
                await _dbContext.SaveChangesAsync();
            }
            else
            {
                _dbContext.LocalUnits.Remove(unit);
                await _dbContext.SaveChangesAsync();
                await _elasticService.DeleteDocumentAsync(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit));
            }

            return true;
        }

        /// <summary>
        /// Delete enterprise unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task<bool> DeleteEnterpriseUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.EnterpriseUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .FirstOrDefault(ent => ent.StatId == statId && ent.StartPeriod >= dataUploadTime);

            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return false;

            var afterUploadEnterpriseUnitsList = _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(ent => ent.ParentId == unit.RegId && ent.StartPeriod >= dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();

            var beforeUploadEnterpriseUnitsList = _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(ent => ent.ParentId == unit.RegId && ent.StartPeriod < dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();

            if (afterUploadEnterpriseUnitsList.Count > 0) return false;

            if (beforeUploadEnterpriseUnitsList.Count > 0)
            {
                await UpdateUnitTask(unit, beforeUploadEnterpriseUnitsList.Last(), userId, StatUnitTypes.EnterpriseUnit);
                _dbContext.EnterpriseUnitHistory.Remove(beforeUploadEnterpriseUnitsList.Last());
                await _dbContext.SaveChangesAsync();
            }

            else
            {
                _dbContext.EnterpriseUnits.Remove(unit);
                await _dbContext.SaveChangesAsync();
                await _elasticService.DeleteDocumentAsync(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit));
            }

            return true;
        }

        /// <summary>
        /// Updates unit to the state before data source upload, reject data source queue/log case
        /// </summary>
        /// <param name="units">Unit</param>
        /// <param name="historyUnits">History unit</param>
        /// <param name="userId">Id of user that rejectes data source queue</param>
        /// <param name="type">Type of statistical unit</param>
        public async Task RangeUpdateUnitsTask(List<StatisticalUnit> units, List<StatisticalUnitHistory> historyUnits, string userId, StatUnitTypes type)
        {
            List<StatisticalUnit> unitsForUpdate = new List<StatisticalUnit>();
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    unitsForUpdate.AddRange(units.Select(Mapper.Map<LegalUnit>));
                    break;
                case StatUnitTypes.LocalUnit:
                    unitsForUpdate.AddRange(units.Select(Mapper.Map<LocalUnit>));
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unitsForUpdate.AddRange(units.Select(Mapper.Map<EnterpriseUnit>));
                    break;
            }

            var actForDelete = new List<ActivityStatisticalUnit>();
            var persForDelete = new List<PersonStatisticalUnit>();
            var countForDelete = new List<CountryStatisticalUnit>();
            foreach (var unit in unitsForUpdate)
            {
                var lastUnit = units.Last(x => x.StatId == unit.StatId);
                var historyUnitLast = historyUnits.Last(x => x.StatId == unit.StatId);

                unit.ActivitiesUnits.ForEach(x => x.UnitId = unit.RegId);
                unit.PersonsUnits.ForEach(x => x.UnitId = unit.RegId);
                unit.ForeignParticipationCountriesUnits.ForEach(x => x.UnitId = unit.RegId);

                actForDelete.AddRange(unit.ActivitiesUnits);
                persForDelete.AddRange(unit.PersonsUnits);
                countForDelete.AddRange(unit.ForeignParticipationCountriesUnits);

                Mapper.Map(historyUnitLast, unit);
                unit.EndPeriod = lastUnit.EndPeriod;
                unit.EditComment =
                    "This unit was edited by data source upload service and then data upload changes rejected";
                unit.RegId = lastUnit.RegId;
                unit.UserId = userId;

                unit.ActivitiesUnits = historyUnitLast.ActivitiesUnits.Select(z => Mapper.Map(z, new ActivityStatisticalUnit())).ToList();
                unit.PersonsUnits = historyUnitLast.PersonsUnits.Select(z => Mapper.Map(z, new PersonStatisticalUnit())).ToList();
                unit.ForeignParticipationCountriesUnits = historyUnitLast.ForeignParticipationCountriesUnits.Select(z => Mapper.Map(z, new CountryStatisticalUnit())).ToList();

                unit.ActivitiesUnits.ForEach(x => x.UnitId = unit.RegId);
                unit.PersonsUnits.ForEach(x => x.UnitId = unit.RegId);
                unit.ForeignParticipationCountriesUnits.ForEach(x => x.UnitId = unit.RegId);
            }
            await _dbContext.BulkDeleteAsync(actForDelete);
            await _dbContext.BulkDeleteAsync(persForDelete);
            await _dbContext.BulkDeleteAsync(countForDelete);

            await _dbContext.BulkInsertAsync(unitsForUpdate.SelectMany(x => x.ActivitiesUnits).ToList());
            await _dbContext.BulkInsertAsync(unitsForUpdate.SelectMany(x => x.PersonsUnits).ToList());
            await _dbContext.BulkInsertAsync(unitsForUpdate.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList());

            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    await _dbContext.BulkUpdateAsync(unitsForUpdate.OfType<LegalUnit>().ToList());
                    break;
                case StatUnitTypes.LocalUnit:
                    await _dbContext.BulkUpdateAsync(unitsForUpdate.OfType<LocalUnit>().ToList());
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    await _dbContext.BulkUpdateAsync(unitsForUpdate.OfType<EnterpriseUnit>().ToList());
                    break;
            }
            await _elasticService.UpsertDocumentList((unitsForUpdate).Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>).ToList());
            unitsForUpdate.Clear();
        }

        /// <summary>
        /// Delete range legal units method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statIds">Ids of stat units</param>
        /// <param name="userId">Id of user for edit unit if there is history</param>
        /// <param name="dataUploadTime">data source upload time</param>
        public async Task<bool> DeleteRangeLegalUnitsFromDb(List<string> statIds, string userId, DateTime? dataUploadTime)
        {
            if (!dataUploadTime.HasValue || string.IsNullOrEmpty(userId)) return false;

            var units = await _dbContext.LegalUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(legU => statIds.Contains(legU.StatId) && legU.StartPeriod >= dataUploadTime)
                .ToListAsync();

            if (!units.Any()) return false;

            var afterUploadLegalUnitsList = await _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(legU => units.Any(x => x.RegId == legU.ParentId) && legU.StartPeriod >= dataUploadTime)
                .OrderBy(legU => legU.StartPeriod)
                .ToListAsync();

            if (afterUploadLegalUnitsList.Any()) return false;

            var beforeUploadLegalUnitsList = await _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(legU => units.Any(x => x.RegId == legU.ParentId) && legU.StartPeriod < dataUploadTime)
                .OrderBy(legU => legU.StartPeriod)
                .ToListAsync();

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                if (beforeUploadLegalUnitsList.Any())
                {
                    await RangeUpdateUnitsTask(units.Cast<StatisticalUnit>().ToList(), beforeUploadLegalUnitsList.Cast<StatisticalUnitHistory>().ToList(), userId, StatUnitTypes.LegalUnit);
                    await _dbContext.BulkDeleteAsync(beforeUploadLegalUnitsList);
                }
                else
                {
                    var localUnitDeleted = await DeleteRangeLocalUnitsFromDb(statIds, userId, dataUploadTime);
                    List<LocalUnit> locals;
                    if (!localUnitDeleted)
                    {
                        locals = await _dbContext.LocalUnits.Where(x => units.Any(z => z.RegId == x.LegalUnitId)).ToListAsync();
                        if (locals.Any())
                        {
                            locals.ForEach(x =>
                            {
                                _commonSvc.TrackUnitHistoryFor<LocalUnit>(x.RegId, userId, ChangeReasons.Edit, "Link to Legal Unit deleted by data source upload service reject functionality", DateTime.Now);
                                x.LegalFormId = null;
                            });
                            await _elasticService.UpsertDocumentList(locals.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>).ToList());
                        }
                    }
                    await _dbContext.BulkDeleteAsync(units);
                    await DeleteRangeEnterpriseUnitsFromDb(statIds, userId, dataUploadTime);
                    await _elasticService.DeleteDocumentRangeAsync(units.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>));
                }
                transaction.Commit();
            }
            return true;
        }

        /// <summary>
        /// Delete range local units method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task<bool> DeleteRangeLocalUnitsFromDb(List<string> statIds, string userId, DateTime? dataUploadTime)
        {
            if (!dataUploadTime.HasValue || string.IsNullOrEmpty(userId)) return false;

            var units = await _dbContext.LocalUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => statIds.Contains(local.StatId) && local.StartPeriod >= dataUploadTime)
                .ToListAsync();

            if (!units.Any())
                return false;

            var afterUploadLocalUnitsList = await _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => units.Any(x => x.RegId == local.ParentId) && local.StartPeriod >= dataUploadTime).OrderBy(local => local.StartPeriod)
                .ToListAsync();

            if (afterUploadLocalUnitsList.Any())
                return false;

            var beforeUploadLocalUnitsList = await _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => units.Any(x => x.RegId == local.ParentId) && local.StartPeriod < dataUploadTime).OrderBy(local => local.StartPeriod)
                .ToListAsync();

            if (beforeUploadLocalUnitsList.Any())
            {
                await RangeUpdateUnitsTask(units.Cast<StatisticalUnit>().ToList(), beforeUploadLocalUnitsList.Cast<StatisticalUnitHistory>().ToList(), userId, StatUnitTypes.LocalUnit);
                await _dbContext.BulkDeleteAsync(beforeUploadLocalUnitsList);
            }
            else
            {
                await _dbContext.BulkDeleteAsync(units);
                await _elasticService.DeleteDocumentRangeAsync(units.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>));
            }

            return true;
        }

        /// <summary>
        /// Delete range enterprise units method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statIds">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task<bool> DeleteRangeEnterpriseUnitsFromDb(List<string> statIds, string userId, DateTime? dataUploadTime)
        {
            if (!dataUploadTime.HasValue || string.IsNullOrEmpty(userId)) return false;

            var units = await _dbContext.EnterpriseUnits.AsNoTracking()
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(ent => statIds.Contains(ent.StatId) && ent.StartPeriod >= dataUploadTime)
                .ToListAsync();

            if (!units.Any()) return false;

            var afterUploadEnterpriseUnitsList = await _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(ent => units.Any(x => x.RegId == ent.ParentId) && ent.StartPeriod >= dataUploadTime)
                .OrderBy(ent => ent.StartPeriod)
                .ToListAsync();

            if (afterUploadEnterpriseUnitsList.Any()) return false;


            var beforeUploadEnterpriseUnitsList = await _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(ent => units.Any(x => x.RegId == ent.ParentId) && ent.StartPeriod < dataUploadTime)
                .OrderBy(ent => ent.StartPeriod)
                .ToListAsync();

            if (beforeUploadEnterpriseUnitsList.Any())
            {
                await RangeUpdateUnitsTask(units.Cast<StatisticalUnit>().ToList(), beforeUploadEnterpriseUnitsList.Cast<StatisticalUnitHistory>().ToList(), userId, StatUnitTypes.EnterpriseUnit);
                await _dbContext.BulkDeleteAsync(beforeUploadEnterpriseUnitsList);
            }

            else
            {
                await _dbContext.BulkDeleteAsync(units);
                await _elasticService.DeleteDocumentRangeAsync(units.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>));
            }

            return true;
        }
    }
}
