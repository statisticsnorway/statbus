using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Dynamic.Core;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.History;
using nscreg.Server.Common.Helpers;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;

namespace nscreg.Server.Common.Services.StatUnit
{
    /// <summary>
    /// Класс сервис удаления
    /// </summary>
    public class DeleteService
    {
        private readonly Common _commonSvc;
        private readonly UserService _userService;
        private readonly Dictionary<StatUnitTypes, Func<int, bool, string, IStatisticalUnit>> _deleteUndeleteActions;
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
        }

        /// <summary>
        /// Удаление/Восстановление  стат. единицы
        /// </summary>
        /// <param name="unitType">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        public void DeleteUndelete(StatUnitTypes unitType, int id, bool toDelete, string userId)
        {
            if (_dataAccessService.CheckWritePermissions(userId, unitType))
            {
                throw new UnauthorizedAccessException();
            }

            var item = Mapper.Map<IStatisticalUnit, ElasticStatUnit>(_commonSvc.GetStatisticalUnitByIdAndType(id, unitType, !toDelete).Result);
            bool isEmployee = _userService.IsInRoleAsync(userId, DefaultRoleNames.Employee).Result;

            if (isEmployee)
            {
                var helper = new StatUnitCheckPermissionsHelper(_dbContext);
                helper.CheckRegionOrActivityContains(userId, item.RegionIds, item.ActivityCategoryIds);
            }
            var unit = _deleteUndeleteActions[unitType](id, toDelete, userId);
            
            _elasticService.EditDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(unit)).Wait();
        }

        /// <summary>
        /// Удаление/Восстановление группы предприятия
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private IStatisticalUnit DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new EnterpriseGroupHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseGroupHistory.Add((EnterpriseGroupHistory) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        /// Удаление/Восстановление  правовой единицы
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private IStatisticalUnit DeleteUndeleteLegalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new LegalUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LegalUnitHistory.Add((LegalUnitHistory) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        /// Удаление/Восстановление  местной единицы
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private IStatisticalUnit DeleteUndeleteLocalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new LocalUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LocalUnitHistory.Add((LocalUnitHistory) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
        }

        /// <summary>
        /// Удаление/Восстановление  предприятия
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private IStatisticalUnit DeleteUndeleteEnterpriseUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return unit;
            var hUnit = new EnterpriseUnitHistory();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseUnitHistory.Add((EnterpriseUnitHistory) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();

            return unit;
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
            var unitForUpdate = type == StatUnitTypes.LegalUnit ? Mapper.Map<LegalUnit>(unit)
                : (type == StatUnitTypes.LocalUnit ? Mapper.Map<LocalUnit>(unit)
                    : Mapper.Map<EnterpriseUnit>(unit));

            Mapper.Map(historyUnit, unitForUpdate);
            unitForUpdate.EndPeriod = unit.EndPeriod;
            unitForUpdate.EditComment =
                "This unit was edited by data source upload service and then data upload changes rejected";
            unitForUpdate.RegId = unit.RegId;
            unitForUpdate.UserId = userId;

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
        }

        /// <summary>
        /// Delete legal unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="userId">Id of user for edit unit if there is history</param>
        /// <param name="dataUploadTime">data source upload time</param>
        public async Task DeleteLegalUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.LegalUnits.AsNoTracking().FirstOrDefault(legU => legU.StatId == statId);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadLegalUnitsList = _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod >= dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();
            var beforeUploadLegalUnitsList = _dbContext.LegalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod < dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();

            EnterpriseUnit enterpriseUnit = null;
            if (afterUploadLegalUnitsList.Count > 0)
            {
                var unitFirst = afterUploadLegalUnitsList.First();
                var historyLocalUnitIds = !string.IsNullOrEmpty(unitFirst.HistoryLocalUnitIds) ? unitFirst.HistoryLocalUnitIds.Split(',') : null;
                if (historyLocalUnitIds?.Length > 0)
                {
                    foreach (var itemHistoryLocalUnit in historyLocalUnitIds)
                    {
                        var localUnit = _dbContext.LocalUnits.AsNoTracking().FirstOrDefault(locU => locU.RegId == int.Parse(itemHistoryLocalUnit) && locU.StartPeriod >= dataUploadTime);
                        var localUnitList = _dbContext.LocalUnitHistory.AsNoTracking().Where(locU => localUnit != null &&
                                                                                                     locU.ParentId == localUnit.RegId && locU.StartPeriod >= dataUploadTime).ToList();
                        localUnitList.Add(Mapper.Map<LocalUnitHistory>(localUnit));
                        if (localUnitList.Count > 0 && localUnitList.First() != null)
                            await DeleteLocalUnitFromDb(localUnitList.First().StatId, userId, dataUploadTime);
                    }
                }

                enterpriseUnit = _dbContext.EnterpriseUnits.AsNoTracking().FirstOrDefault(entU => unitFirst.EnterpriseUnitRegId != null && entU.RegId == unitFirst.EnterpriseUnitRegId && entU.StartPeriod >= dataUploadTime);

            }

            if (beforeUploadLegalUnitsList.Count > 0)
            {
                await UpdateUnitTask(unit, beforeUploadLegalUnitsList.Last(), userId, StatUnitTypes.LegalUnit);
                _dbContext.LegalUnitHistory.Remove(beforeUploadLegalUnitsList.Last());
            }
            else
            {
                var local = _dbContext.LocalUnits.FirstOrDefault(x => x.LegalUnitId == unit.RegId);
                if (local != null)
                    _dbContext.LocalUnits.Remove(local);
                var entUnit =
                    _dbContext.EnterpriseUnits.FirstOrDefault(x => x.RegId == unit.EnterpriseUnitRegId);

                _dbContext.LegalUnits.Remove(unit);

                int legalCountOfEntUnit =
                    _dbContext.LegalUnits.Count(x => x.EnterpriseUnitRegId == entUnit.RegId);
                if (entUnit != null && legalCountOfEntUnit == 1)
                    _dbContext.EnterpriseUnits.Remove(entUnit);
            }

            _dbContext.LegalUnitHistory.RemoveRange(afterUploadLegalUnitsList);
            await _dbContext.SaveChangesAsync();

            if (enterpriseUnit != null && enterpriseUnit.LegalUnits.Count == 0) await DeleteEnterpriseUnitFromDb(enterpriseUnit.StatId, userId, dataUploadTime);
        }

        /// <summary>
        /// Delete local unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteLocalUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.LocalUnits.AsNoTracking().FirstOrDefault(local => local.StatId == statId && local.StartPeriod >= dataUploadTime);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod >= dataUploadTime).OrderBy(local => local.StartPeriod).ToList();
            var beforeUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x=>x.PersonsUnits)
                .Include(x=>x.ActivitiesUnits)
                .Include(x=>x.ForeignParticipationCountriesUnits)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod < dataUploadTime).OrderBy(local => local.StartPeriod).ToList();

            if (beforeUploadLocalUnitsList.Count > 0)
            {
                await UpdateUnitTask(unit, beforeUploadLocalUnitsList.Last(), userId, StatUnitTypes.LocalUnit);
                _dbContext.LocalUnitHistory.Remove(beforeUploadLocalUnitsList.Last());
            }
            else
            {
                _dbContext.LocalUnits.Remove(unit);
            }
            _dbContext.LocalUnitHistory.RemoveRange(afterUploadLocalUnitsList);
            await _dbContext.SaveChangesAsync();
        }

        /// <summary>
        /// Delete enterprise unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteEnterpriseUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.EnterpriseUnits.AsNoTracking().FirstOrDefault(ent => ent.StatId == statId && ent.StartPeriod >= dataUploadTime);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadEnterpriseUnitsList = _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Where(ent => ent.ParentId == unit.RegId && ent.StartPeriod >= dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();
            var beforeUploadEnterpriseUnitsList = _dbContext.EnterpriseUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Where(ent => ent.ParentId == unit.RegId && ent.StartPeriod < dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();
            
            
            if (beforeUploadEnterpriseUnitsList.Count > 0)
            {
                await UpdateUnitTask(unit, beforeUploadEnterpriseUnitsList.Last(), userId, StatUnitTypes.EnterpriseUnit);
                _dbContext.EnterpriseUnitHistory.Remove(beforeUploadEnterpriseUnitsList.Last());
            }
            else
            {
                _dbContext.EnterpriseUnits.Remove(unit);
            }
            _dbContext.EnterpriseUnitHistory.RemoveRange(afterUploadEnterpriseUnitsList);
            await _dbContext.SaveChangesAsync();
        }

        /// <summary>
        /// Removing statunit from elastic
        /// </summary>
        /// <param name="elasticItemId">index of item in elastic</param>
        /// <param name="statUnitTypes">types of statunits</param>
        /// <returns></returns>
        public Task DeleteUnitFromElasticAsync(string elasticItemId, List<StatUnitTypes> statUnitTypes)
        {
            return _elasticService.DeleteDocumentAsync(elasticItemId, statUnitTypes);
        }
    }
}
