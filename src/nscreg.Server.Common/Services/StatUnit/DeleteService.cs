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

            if (afterUploadLegalUnitsList.Count > 0) return false;
            
            if (beforeUploadLegalUnitsList.Count > 0)
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
                    _commonSvc.TrackUnithistoryFor<LocalUnit>(local.RegId, userId, ChangeReasons.Edit, "Link to Legal Unit deleted by data source upload service reject functionality", DateTime.Now);
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
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .FirstOrDefault(local => local.StatId == statId && local.StartPeriod >= dataUploadTime);
            if (unit == null || dataUploadTime == null || string.IsNullOrEmpty(userId)) return false;
            var afterUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x => x.PersonsUnits)
                .Include(x => x.ActivitiesUnits)
                .Include(x => x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod >= dataUploadTime).OrderBy(local => local.StartPeriod).ToList();
            var beforeUploadLocalUnitsList = _dbContext.LocalUnitHistory
                .Include(x=>x.PersonsUnits)
                .Include(x=>x.ActivitiesUnits)
                .Include(x=>x.ForeignParticipationCountriesUnits)
                .Include(x => x.Address)
                .Include(x => x.PostalAddress)
                .Include(x => x.ActualAddress)
                .Where(local => local.ParentId == unit.RegId && local.StartPeriod < dataUploadTime).OrderBy(local => local.StartPeriod).ToList();

            if (afterUploadLocalUnitsList.Count > 0) return false;

            if (beforeUploadLocalUnitsList.Count > 0)
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
    }
}
