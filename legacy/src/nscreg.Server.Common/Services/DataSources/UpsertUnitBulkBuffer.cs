using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
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
                var addresses = Buffer.SelectMany(x => new[] { x.ActualAddress, x.PostalAddress }).Where(x => x != null).Distinct(new IdComparer<Address>()).ToList();
                var activityUnits = Buffer.SelectMany(x => x.ActivitiesUnits).ToList();
                var activities = activityUnits.Select(z => z.Activity).Distinct(new IdComparer<Activity>()).ToList();

                var personUnits = Buffer.SelectMany(x => x.PersonsUnits).ToList();
                var persons = personUnits.Select(z => z.Person).Distinct(new IdComparer<Person>()).ToList();

                var foreignCountry = Buffer.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList();

                // Note: We call SaveChangesAsync seperately after each change to the DB
                // because of a key related issue in Entity Framework that requires us to do so               
                await _context.Activities.AddRangeAsync(activities.Where(x => x.Id == 0));
                await _context.SaveChangesAsync();
                await _context.Activities.AddRangeAsync(activities.Where(x => x.Id != 0));
                await _context.SaveChangesAsync();
                await _context.Persons.AddRangeAsync(persons.Where(x => x.Id == 0));
                await _context.SaveChangesAsync();
                await _context.Persons.AddRangeAsync(persons.Where(x => x.Id != 0));
                await _context.SaveChangesAsync();
                _context.Address.UpdateRange(addresses);
                await _context.SaveChangesAsync();

                Buffer.ForEach(unit =>
                {
                    unit.ActualAddressId = unit.ActualAddress?.Id;
                    unit.PostalAddressId = unit.PostalAddress?.Id;
                    unit.EndPeriod = DateTime.MaxValue;
                });
                var enterprises = Buffer.OfType<EnterpriseUnit>().ToList();

                var groups = enterprises.Select(x => x.EnterpriseGroup).Where(z => z != null).ToList();
                _context.EnterpriseGroups.UpdateRange(groups);
                await _context.SaveChangesAsync();

                enterprises.ForEach(x => x.EntGroupId = x.EnterpriseGroup?.RegId);
                _context.EnterpriseUnits.UpdateRange(enterprises);
                await _context.SaveChangesAsync();

                var legals = Buffer.OfType<LegalUnit>().ToList();
                legals.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit?.RegId);

                _context.LegalUnits.UpdateRange(legals);
                await _context.SaveChangesAsync();

                var locals = Buffer.OfType<LocalUnit>().ToList();
                locals.ForEach(x => x.LegalUnitId = x.LegalUnit?.RegId);           

                _context.LocalUnits.UpdateRange(locals);
                await _context.SaveChangesAsync();

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

                _context.LegalUnits.UpdateRange(legals);
                await _context.SaveChangesAsync();

                var legalsOfEnterprises = await _context.LegalUnits.Where(leu => legalStatIds.Contains(leu.StatId))
                    .Select(x => new { x.StatId, x.RegId }).ToListAsync();

                enterprises.Join(legalsOfEnterprises, e => e.StatId,
                    l => l.StatId, (enterpriseUnit, legalsList) => (enterpriseUnit: enterpriseUnit, legalsList: legalsList)).ForEach(z =>
                        z.enterpriseUnit.HistoryLegalUnitIds = string.Join(",", z.legalsList.RegId)
                    );

                _context.EnterpriseUnits.UpdateRange(enterprises);
                await _context.SaveChangesAsync();

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

                _context.ActivityStatisticalUnits.UpdateRange(activityUnits);
                await _context.SaveChangesAsync();
                _context.PersonStatisticalUnits.UpdateRange(personUnits);
                await _context.SaveChangesAsync();
                _context.CountryStatisticalUnits.UpdateRange(foreignCountry);
                await _context.SaveChangesAsync();

                _context.EnterpriseUnits.RemoveRange(BufferToDelete);
                await _context.SaveChangesAsync();

                if (HistoryBuffer.Any())
                {
                    var localUnitHistory = HistoryBuffer.OfType<LocalUnitHistory>().ToList();
                    var legalUnitHistory = HistoryBuffer.OfType<LegalUnitHistory>().ToList();
                    var enterpriseUnitHistory = HistoryBuffer.OfType<EnterpriseUnitHistory>().ToList();

                    await _context.LocalUnitHistory.AddRangeAsync(localUnitHistory);
                    await _context.SaveChangesAsync();
                    await _context.LegalUnitHistory.AddRangeAsync(legalUnitHistory);
                    await _context.SaveChangesAsync();
                    await _context.EnterpriseUnitHistory.AddRangeAsync(enterpriseUnitHistory);
                    await _context.SaveChangesAsync();

                    var concatHistories = localUnitHistory.Cast<StatisticalUnitHistory>()
                        .Concat(legalUnitHistory)
                        .Concat(enterpriseUnitHistory).ToList();

                    var statUnitHistories = HistoryBuffer.OfType<StatisticalUnitHistory>().ToList();

                    var activitiesHistory = statUnitHistories.SelectMany(x => x.Activities.Distinct(new IdComparer<ActivityHistory>()))
                            .ToList();                

                    await _context.ActivitiesHistory.AddRangeAsync(activitiesHistory);
                    await _context.SaveChangesAsync();

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
                    
                    await _context.ActivityStatisticalUnitHistory.AddRangeAsync(statUnitHistories.SelectMany(x => x.ActivitiesUnits).ToList());
                    await _context.SaveChangesAsync();
                    await _context.PersonStatisticalUnitHistory.AddRangeAsync(statUnitHistories.SelectMany(x => x.PersonsUnits).ToList());
                    await _context.SaveChangesAsync();
                    await _context.CountryStatisticalUnitHistory.AddRangeAsync(statUnitHistories.SelectMany(x => x.ForeignParticipationCountriesUnits).ToList());
                    await _context.SaveChangesAsync();
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
