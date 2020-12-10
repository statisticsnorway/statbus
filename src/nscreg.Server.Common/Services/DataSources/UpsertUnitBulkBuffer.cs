using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using EFCore.BulkExtensions;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Data.Entities.History;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    public class UpsertUnitBulkBuffer
    {
        private DataAccessPermissions _permissions;
        private bool _isEnabledFlush = true;
        private List<StatisticalUnit> Buffer { get; }
        private List<EnterpriseUnit> BufferToDelete { get; }
        private List<IStatisticalUnitHistory> HistoryBuffer { get; }
        private readonly NSCRegDbContext _context;
        public ElasticService ElasticSearchService { get; }
        private readonly int _maxBulkOperationsBufferedCount;
        private DataSourceQueue _dataSourceQueue;
        public UpsertUnitBulkBuffer(NSCRegDbContext context, ElasticService elasticSearchService, DataAccessPermissions permissions, DataSourceQueue queue, int maxBufferCount = 1000)
        {

            _permissions = permissions;
            HistoryBuffer = new List<IStatisticalUnitHistory>();
            BufferToDelete = new List<EnterpriseUnit>();
            Buffer = new List<StatisticalUnit>();
            _context = context;
            ElasticSearchService = elasticSearchService;
            _dataSourceQueue = queue;
            _maxBulkOperationsBufferedCount = maxBufferCount;
        }

        public void AddToDeleteBuffer(EnterpriseUnit unit)
        {
            BufferToDelete.Add(unit);
        }

        public void AddToHistoryBuffer(IStatisticalUnitHistory unitHistory)
        {
            HistoryBuffer.Add(unitHistory);

        }
        public async Task AddToBufferAsync(StatisticalUnit element)
        {
            Buffer.Add(element);
            if (Buffer.Count >= _maxBulkOperationsBufferedCount && _isEnabledFlush)
            {
                await FlushAsync();
            }
        }

        public async Task FlushAsync()
        {
            using (var transaction = _context.Database.BeginTransaction())
            {
                var bulkConfig = new BulkConfig { SetOutputIdentity = true, PreserveInsertOrder = true, BulkCopyTimeout = 0 };
                
                var addresses = Buffer.SelectMany(x => new[] { x.Address, x.ActualAddress, x.PostalAddress }).Where(x => x != null).Distinct(new IdComparer<Address>()).ToList();
                var activityUnits = Buffer.SelectMany(x => x.ActivitiesUnits).ToList();
                var activities = activityUnits.Select(z => z.Activity).Distinct(new IdComparer<Activity>()).ToList();

                var personUnits = Buffer.SelectMany(x => x.PersonsUnits).ToList();
                var persons = personUnits.Select(z => z.Person).Distinct(new IdComparer<Person>()).ToList();

                var foreignCountry = Buffer.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList();

                await _context.BulkInsertAsync(activities.Where(x => x.Id == 0).ToList(), bulkConfig);
                await _context.BulkUpdateAsync(activities.Where(x => x.Id != 0).ToList());
                await _context.BulkInsertAsync(persons.Where(x => x.Id == 0).ToList(), bulkConfig);
                await _context.BulkUpdateAsync(persons.Where(x => x.Id != 0).ToList());
                await _context.BulkInsertOrUpdateAsync(addresses, bulkConfig);
                
                Buffer.ForEach(unit =>
                {
                    unit.AddressId = unit.Address?.Id;
                    unit.ActualAddressId = unit.ActualAddress?.Id;
                    unit.PostalAddressId = unit.PostalAddress?.Id;
                });
                var enterprises = Buffer.OfType<EnterpriseUnit>().ToList();

                var groups = enterprises.Select(x => x.EnterpriseGroup).Where(z => z != null).ToList();
                await _context.BulkInsertOrUpdateAsync(groups, bulkConfig);

                enterprises.ForEach(x => x.EntGroupId = x.EnterpriseGroup?.RegId);
                await _context.BulkInsertOrUpdateAsync(enterprises, bulkConfig);

                var legals = Buffer.OfType<LegalUnit>().ToList();
                legals.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit?.RegId);

                await _context.BulkInsertOrUpdateAsync(legals, bulkConfig);

                var locals = Buffer.OfType<LocalUnit>().ToList();
                locals.ForEach(x => x.LegalUnitId = x.LegalUnit?.RegId);
                await _context.BulkInsertOrUpdateAsync(locals, bulkConfig);

                var legalStatIds = new List<string>();

                var hasAccess = StatUnit.Common.HasAccess<LegalUnit>(_permissions, v => v.LocalUnits);

                legals.ForEach(changedUnit =>
                {
                    if (changedUnit.LocalUnits != null && changedUnit.LocalUnits.Any() && hasAccess)
                    {
                        changedUnit.HistoryLocalUnitIds = string.Join(",", changedUnit.LocalUnits.Select(x => x.RegId));
                    }

                    if (changedUnit.EnterpriseUnitRegId.HasValue)
                    {
                        legalStatIds.Add(changedUnit.StatId);
                    }
                });

                await _context.BulkUpdateAsync(legals, bulkConfig);

                var legalsOfEnterprises = await _context.LegalUnits.Where(leu => legalStatIds.Contains(leu.StatId))
                    .Select(x => new { x.StatId, x.RegId }).ToListAsync();

                enterprises.Join(legalsOfEnterprises, e => e.StatId,
                    l => l.StatId, (enterpriseUnit, legalsList) => (enterpriseUnit: enterpriseUnit, legalsList: legalsList)).ForEach(z =>
                         z.enterpriseUnit.HistoryLegalUnitIds = string.Join(",", z.legalsList.RegId)
                    );

                await _context.BulkUpdateAsync(enterprises, bulkConfig);

                Buffer.ForEach(buf => buf.ActivitiesUnits.ForEach(au =>
                {
                    au.ActivityId = au.Activity.Id;
                    au.UnitId = buf.RegId;
                }));
                Buffer.ForEach(x => x.ForeignParticipationCountriesUnits.ForEach(z => z.UnitId = x.RegId));

                Buffer.ForEach(z => z.PersonsUnits.ForEach(x =>
                {
                    x.UnitId = z.RegId;
                    x.PersonId = x.Person.Id;
                    x.PersonTypeId = x.Person.Role;
                }));

                await _context.BulkInsertOrUpdateAsync(activityUnits);
                await _context.BulkInsertOrUpdateAsync(personUnits);
                await _context.BulkInsertOrUpdateAsync(foreignCountry);
                await _context.BulkDeleteAsync(BufferToDelete);

                ///History
                await _context.BulkInsertOrUpdateAsync(HistoryBuffer.OfType<LocalUnitHistory>().ToList(), bulkConfig);
                await _context.BulkInsertOrUpdateAsync(HistoryBuffer.OfType<LegalUnitHistory>().ToList(), bulkConfig);
                await _context.BulkInsertOrUpdateAsync(HistoryBuffer.OfType<EnterpriseUnitHistory>().ToList(), bulkConfig);

                var statUnitHistories = HistoryBuffer.OfType<StatisticalUnitHistory>().ToList();

                statUnitHistories.ForEach(x => x.ActivitiesUnits.ForEach(z => z.UnitId = x.RegId));
                statUnitHistories.ForEach(x => x.PersonsUnits.ForEach(z => z.UnitId = x.RegId));
                statUnitHistories.ForEach(x => x.ForeignParticipationCountriesUnits.ForEach(z => z.UnitId = x.RegId));

                await _context.BulkInsertOrUpdateAsync(statUnitHistories.SelectMany(x => x.ActivitiesUnits).ToList());
                await _context.BulkInsertOrUpdateAsync(statUnitHistories.SelectMany(x => x.PersonsUnits).ToList());
                await _context.BulkInsertOrUpdateAsync(statUnitHistories.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList());


                if (Buffer.Any())
                {
                    var entities = Buffer.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>)
                        .Concat(groups.Select(Mapper.Map<IStatisticalUnit, ElasticStatUnit>)).ToList();
                    await ElasticSearchService.UpsertDocumentList(entities);
                }
                transaction.Commit();

                switch (_dataSourceQueue.DataSource.StatUnitType)
                {
                    case StatUnitTypes.LocalUnit:
                        _dataSourceQueue.SkipLinesCount += locals.Count();
                        break;
                    case StatUnitTypes.LegalUnit:
                        _dataSourceQueue.SkipLinesCount += legals.Count();
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        _dataSourceQueue.SkipLinesCount += enterprises.Count();
                        break;
                }
            }

            Buffer.Clear();
            BufferToDelete.Clear();
            HistoryBuffer.Clear();
        }
        public void DisableFlushing()
        {
            _isEnabledFlush = false;
        }
        public void EnableFlushing()
        {
            _isEnabledFlush = true;
        }
        
    }
}
