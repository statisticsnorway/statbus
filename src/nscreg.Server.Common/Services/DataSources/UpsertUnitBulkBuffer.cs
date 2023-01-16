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
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Data.Entities.History;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Extensions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Server.Common.Services.DataSources
{
    public class UpsertUnitBulkBuffer
    {
        private readonly DataAccessPermissions _permissions;
        private bool _isEnabledFlush = true;
        private List<StatisticalUnit> Buffer { get; }
        private List<EnterpriseUnit> BufferToDelete { get; }
        private List<IStatisticalUnitHistory> HistoryBuffer { get; }
        private readonly NSCRegDbContext _context;
        public IElasticUpsertService ElasticSearchService { get; }
        private readonly int _maxBulkOperationsBufferedCount;
        private readonly DataSourceQueue _dataSourceQueue;
        private readonly IMapper _mapper;

        public UpsertUnitBulkBuffer(NSCRegDbContext context, IElasticUpsertService elasticSearchService,
            DataAccessPermissions permissions, DataSourceQueue queue, IMapper mapper, int maxBufferCount)
        {
            _permissions = permissions;
            HistoryBuffer = new List<IStatisticalUnitHistory>();
            BufferToDelete = new List<EnterpriseUnit>();
            Buffer = new List<StatisticalUnit>();
            _context = context;
            ElasticSearchService = elasticSearchService;
            _dataSourceQueue = queue;
            _maxBulkOperationsBufferedCount = maxBufferCount;
            _mapper = mapper;
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
                var bulkConfig = new BulkConfig { PreserveInsertOrder = true, SetOutputIdentity = true, BulkCopyTimeout = 0 };

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
                    unit.EndPeriod = DateTime.MaxValue;
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

                var hasAccess = CommonService.HasAccess<LegalUnit>(_permissions, v => v.LocalUnits);

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

                if (HistoryBuffer.Any())
                {
                    var localUnitHistory = HistoryBuffer.OfType<LocalUnitHistory>().ToList();
                    var legalUnitHistory = HistoryBuffer.OfType<LegalUnitHistory>().ToList();
                    var enterpriseUnitHistory = HistoryBuffer.OfType<EnterpriseUnitHistory>().ToList();

                    var historyBulkConfig = new BulkConfig() { SetOutputIdentity = true, PreserveInsertOrder = false };

                    await _context.BulkInsertAsync(localUnitHistory, historyBulkConfig);
                    await _context.BulkInsertAsync(legalUnitHistory, historyBulkConfig);
                    await _context.BulkInsertAsync(enterpriseUnitHistory, historyBulkConfig);

                    var concatHistories = localUnitHistory.Cast<StatisticalUnitHistory>()
                        .Concat(legalUnitHistory)
                        .Concat(enterpriseUnitHistory).ToList();

                    var statUnitHistories = HistoryBuffer.OfType<StatisticalUnitHistory>().ToList();

                    var activitiesHistory = statUnitHistories.SelectMany(x => x.Activities.Distinct(new IdComparer<ActivityHistory>()))
                            .ToList();

                    await _context.BulkInsertAsync(activitiesHistory, historyBulkConfig);
                    statUnitHistories.GroupJoin(concatHistories, concatHistory => concatHistory.StatId, statUnitHistory => statUnitHistory.StatId, (stathistory, statCollection) => (stathistory: stathistory, statCollection: statCollection)).ForEach(x =>
                    {
                        var statColl = x.statCollection.FirstOrDefault();
                        statColl.ActivitiesUnits = x.stathistory.ActivitiesUnits;
                        statColl.PersonsUnits = x.stathistory.PersonsUnits;
                        statColl.ForeignParticipationCountriesUnits = x.stathistory.ForeignParticipationCountriesUnits;

                        activitiesHistory.GroupJoin(statColl.Activities, inner => inner.ParentId, outer => outer.ParentId, (activity, collection) => (activity: activity, collection: collection)).ForEach(gr =>
                       {
                           var activity = gr.collection.FirstOrDefault();
                           if (activity != null)
                           {
                               activity.Id = gr.activity.Id;
                           }
                           else
                           {
                               activity = gr.activity;
                           }
                       });
                        statColl.ActivitiesUnits.ForEach(y => { y.ActivityId = y.Activity.Id; y.UnitId = statColl.RegId; });
                        statColl.PersonsUnits.ForEach(y => y.UnitId = statColl.RegId);
                        statColl.ForeignParticipationCountriesUnits.ForEach(y => y.UnitId = statColl.RegId);
                    });

                    await _context.BulkInsertAsync(statUnitHistories.SelectMany(x => x.ActivitiesUnits).ToList());
                    await _context.BulkInsertAsync(statUnitHistories.SelectMany(x => x.PersonsUnits).ToList());
                    await _context.BulkInsertAsync(statUnitHistories.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList());
                }

                if (Buffer.Any())
                {
                    var entities = Buffer.Select(x => _mapper.Map<IStatisticalUnit, ElasticStatUnit>(x))
                        .Concat(groups.Select(_mapper.Map<IStatisticalUnit, ElasticStatUnit>)).ToList();
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
