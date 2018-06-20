using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
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
        private readonly Dictionary<StatUnitTypes, Action<int, bool, string>> _deleteUndeleteActions;
        private readonly NSCRegDbContext _dbContext;

        public DeleteService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _deleteUndeleteActions = new Dictionary<StatUnitTypes, Action<int, bool, string>>
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
            _deleteUndeleteActions[unitType](id, toDelete, userId);
        }

        /// <summary>
        /// Удаление/Восстановление группы предприятия
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private void DeleteUndeleteEnterpriseGroupUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.EnterpriseGroups.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseGroup();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseGroups.Add((EnterpriseGroup) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        /// <summary>
        /// Удаление/Восстановление  правовой единицы
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private void DeleteUndeleteLegalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LegalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LegalUnits.Add((LegalUnit) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        /// <summary>
        /// Удаление/Восстановление  местной единицы
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private void DeleteUndeleteLocalUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new LocalUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.LocalUnits.Add((LocalUnit) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
        }

        /// <summary>
        /// Удаление/Восстановление  предприятия
        /// </summary>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="toDelete">Флаг удалённости</param>
        /// <param name="userId">Id пользователя</param>
        private void DeleteUndeleteEnterpriseUnit(int id, bool toDelete, string userId)
        {
            var unit = _dbContext.StatisticalUnits.Find(id);
            if (unit.IsDeleted == toDelete) return;
            var hUnit = new EnterpriseUnit();
            Mapper.Map(unit, hUnit);
            unit.IsDeleted = toDelete;
            unit.UserId = userId;
            unit.EditComment = null;
            unit.ChangeReason = toDelete ? ChangeReasons.Delete : ChangeReasons.Undelete;
            _dbContext.EnterpriseUnits.Add((EnterpriseUnit) Common.TrackHistory(unit, hUnit));
            _dbContext.SaveChanges();
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
            var unitForUpdate = type == StatUnitTypes.LegalUnit ? Mapper.Map<LegalUnit>(historyUnit)
                : (type == StatUnitTypes.LocalUnit ? Mapper.Map<LocalUnit>(historyUnit)
                    : Mapper.Map<EnterpriseUnit>(historyUnit));

            unitForUpdate.EndPeriod = unit.EndPeriod;
            unitForUpdate.EditComment =
                "This unit was edited by data source upload service and then data upload changes rejected";
            unitForUpdate.RegId = unit.RegId;
            unitForUpdate.ParentId = unit.ParentId;
            unitForUpdate.Parent = unit.Parent;
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
            var unit = _dbContext.LegalUnits.AsNoTracking().FirstOrDefault(legU => legU.StatId == statId && legU.ParentId == null);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadLegalUnitsList = _dbContext.LegalUnits.Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod >= dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();
            var beforeUploadLegalUnitsList = _dbContext.LegalUnits.Where(legU => legU.ParentId == unit.RegId && legU.StartPeriod < dataUploadTime).OrderBy(legU => legU.StartPeriod).ToList();

            afterUploadLegalUnitsList.Add(unit);

            var unitFirst = afterUploadLegalUnitsList.First();
            var historyLocalUnitIds = !string.IsNullOrEmpty(unitFirst.HistoryLocalUnitIds) ? unitFirst.HistoryLocalUnitIds.Split(',') : null;
            if (historyLocalUnitIds?.Length > 0)
            {
                foreach (var itemHistoryLocalUnit in historyLocalUnitIds)
                {
                    var localUnit = _dbContext.LocalUnits.AsNoTracking().FirstOrDefault(locU => locU.RegId == int.Parse(itemHistoryLocalUnit) && locU.StartPeriod >= dataUploadTime);
                    var localUnitList = _dbContext.LocalUnits.AsNoTracking().Where(locU => localUnit != null &&
                        locU.ParentId == localUnit.RegId && locU.StartPeriod >= dataUploadTime).ToList();
                    localUnitList.Add(localUnit);
                    if (localUnitList.Count > 0 && localUnitList.First() != null)
                        await DeleteLocalUnitFromDb(localUnitList.First().StatId, userId, dataUploadTime);
                }
            }

            var enterpriseUnit = _dbContext.EnterpriseUnits.AsNoTracking().FirstOrDefault(entU => unitFirst.EnterpriseUnitRegId != null && entU.RegId == unitFirst.EnterpriseUnitRegId && entU.StartPeriod >= dataUploadTime && entU.ParentId == null);
            
            if (beforeUploadLegalUnitsList.Count > 0)
            {
                afterUploadLegalUnitsList.Remove(unit);
                await UpdateUnitTask(unit, beforeUploadLegalUnitsList.Last(), userId, StatUnitTypes.LegalUnit);
            }
            
            _dbContext.LegalUnits.RemoveRange(afterUploadLegalUnitsList);
            await _dbContext.SaveChangesAsync();

            if (enterpriseUnit != null) await DeleteEnterpriseUnitFromDb(enterpriseUnit.StatId, userId, dataUploadTime);
        }

        /// <summary>
        /// Delete local unit method (when revise on data source queue page), deletes unit from database
        /// </summary>
        /// <param name="statId">Id of stat unit</param>
        /// <param name="dataUploadTime">data source upload time</param>
        /// <param name="userId">Id of user</param>
        public async Task DeleteLocalUnitFromDb(string statId, string userId, DateTime? dataUploadTime)
        {
            var unit = _dbContext.LocalUnits.AsNoTracking().FirstOrDefault(local => local.StatId == statId && local.ParentId == null && local.StartPeriod >= dataUploadTime);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadLocalUnitsList = _dbContext.LocalUnits.Where(local => local.ParentId == unit.RegId && local.StartPeriod >= dataUploadTime).OrderBy(local => local.StartPeriod).ToList();
            var beforeUploadLocalUnitsList = _dbContext.LocalUnits.Where(local => local.ParentId == unit.RegId && local.StartPeriod < dataUploadTime).OrderBy(local => local.StartPeriod).ToList();

            afterUploadLocalUnitsList.Add(unit);
            if (beforeUploadLocalUnitsList.Count > 0)
            {
                afterUploadLocalUnitsList.Remove(unit);
                await UpdateUnitTask(unit, beforeUploadLocalUnitsList.Last(), userId, StatUnitTypes.LocalUnit);
            }
            _dbContext.LocalUnits.RemoveRange(afterUploadLocalUnitsList);
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
            var unit = _dbContext.EnterpriseUnits.AsNoTracking().FirstOrDefault(ent => ent.StatId == statId && ent.ParentId == null && ent.StartPeriod >= dataUploadTime);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return;
            var afterUploadEnterpriseUnitsList = _dbContext.EnterpriseUnits.Where(ent => ent.ParentId == ent.RegId && ent.StartPeriod >= dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();
            var beforeUploadEnterpriseUnitsList = _dbContext.EnterpriseUnits.Where(ent => ent.ParentId == ent.RegId && ent.StartPeriod < dataUploadTime).OrderBy(ent => ent.StartPeriod).ToList();

            afterUploadEnterpriseUnitsList.Add(unit);
            if (beforeUploadEnterpriseUnitsList.Count > 0)
            {
                afterUploadEnterpriseUnitsList.Remove(unit);
                await UpdateUnitTask(unit, beforeUploadEnterpriseUnitsList.Last(), userId, StatUnitTypes.EnterpriseUnit);
            }
            _dbContext.EnterpriseUnits.RemoveRange(afterUploadEnterpriseUnitsList);
            await _dbContext.SaveChangesAsync();
        }
    }
}
