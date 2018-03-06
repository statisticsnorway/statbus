using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Services.DataSources
{
    public class SaveManager
    {
        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _createByType;

        private readonly QueueService _queueSvc;

        private readonly Dictionary<DataSourceUploadTypes,
                Func<StatisticalUnit, DataSource, string, Task<(string, bool)>>>
            _saveActionsMap;

        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>> _updateByType;
        private NSCRegDbContext _ctx;

        public SaveManager(NSCRegDbContext context, QueueService queueService, CreateService createSvc,
            EditService editSvc)
        {
            _ctx = context;
            _queueSvc = queueService;
            _saveActionsMap =
                new Dictionary<DataSourceUploadTypes, Func<StatisticalUnit, DataSource, string, Task<(string, bool)>>>
                {
                    [DataSourceUploadTypes.Activities] = SaveActivitiesUploadAsync,
                    [DataSourceUploadTypes.StatUnits] = SaveStatUnitsUpload
                };
            _createByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) =>
                    createSvc.CreateLegalUnit(Mapper.Map<LegalUnitCreateM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) =>
                    createSvc.CreateLocalUnit(Mapper.Map<LocalUnitCreateM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) =>
                    createSvc.CreateEnterpriseUnit(Mapper.Map<EnterpriseUnitCreateM>(unit), userId)
            };
            _updateByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, string, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, userId) =>
                    editSvc.EditLegalUnit(Mapper.Map<LegalUnitEditM>(unit), userId),
                [StatUnitTypes.LocalUnit] = (unit, userId) =>
                    editSvc.EditLocalUnit(Mapper.Map<LocalUnitEditM>(unit), userId),
                [StatUnitTypes.EnterpriseUnit] = (unit, userId) =>
                    editSvc.EditEnterpriseUnit(Mapper.Map<EnterpriseUnitEditM>(unit), userId)
            };
        }

        private async Task<(string, bool)> SaveActivitiesUploadAsync(StatisticalUnit parsedUnit, DataSource dataSource, string userId)
        {
            var originalUnit = await _ctx.StatisticalUnits
                .Include(x => x.ActivitiesUnits)
                .ThenInclude(x => x.Activity)
                .FirstAsync(x => x.RegId == parsedUnit.RegId);

            var canCreate = dataSource.AllowedOperations == DataSourceAllowedOperation.Create ||
                            dataSource.AllowedOperations == DataSourceAllowedOperation.CreateAndAlter;
            var canUpdate = dataSource.AllowedOperations == DataSourceAllowedOperation.Alter ||
                            dataSource.AllowedOperations == DataSourceAllowedOperation.CreateAndAlter;

            foreach (var activityUnit in parsedUnit.ActivitiesUnits)
                if (activityUnit.Activity.Id != 0 && canUpdate)
                    UpdateActivity(activityUnit);
                else if (canCreate)
                    CreateActivity(activityUnit);

            try
            {
                await _ctx.SaveChangesAsync();
            }
            catch (Exception ex)
            {
                return (ex.Message, false);
            }
            return (null, true);

            void UpdateActivity(ActivityStatisticalUnit activityUnit)
            {
                var toUpdate = originalUnit.ActivitiesUnits.First(x => x.ActivityId == activityUnit.Activity.Id).Activity;
                toUpdate.UpdatedDate = DateTime.Now;
                toUpdate.UpdatedBy = userId;
                Mapper.Map(activityUnit.Activity, toUpdate);
            }

            void CreateActivity(ActivityStatisticalUnit activityUnit)
            {
                _ctx.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit()
                {
                    Activity = activityUnit.Activity,
                    Unit = originalUnit
                });
                activityUnit.Activity.IdDate = DateTime.Now;
                activityUnit.Activity.UpdatedDate = DateTime.Now;
                activityUnit.Activity.UpdatedBy = userId;
            }

        }

        private async Task<(string, bool)> SaveStatUnitsUpload(StatisticalUnit parsedUnit, DataSource dataSource,
            string userId)
        {
            var unitExists = await _queueSvc.CheckIfUnitExists(dataSource.StatUnitType, parsedUnit.StatId);

            if (dataSource.Priority != DataSourcePriority.Trusted &&
                (dataSource.Priority != DataSourcePriority.Ok || unitExists))
                return (null, false);

            var saveAction =
                unitExists ? _updateByType[dataSource.StatUnitType] : _createByType[dataSource.StatUnitType];

            try
            {
                await saveAction(parsedUnit, userId);
            }
            catch (Exception ex)
            {
                return (ex.Message, false);
            }
            return (null, true);
        }

        public async Task<(string, bool)> SaveUnit(StatisticalUnit parsedUnit, DataSource dataSource, string userId)
        {
            return await _saveActionsMap[dataSource.DataSourceUploadType](parsedUnit, dataSource, userId);
        }
    }
}
