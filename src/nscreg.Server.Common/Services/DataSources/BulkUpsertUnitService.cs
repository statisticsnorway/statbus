using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Helpers;
using nscreg.Utilities.Extensions;
using Activity = nscreg.Data.Entities.Activity;

namespace nscreg.Server.Common.Services.DataSources
{
    public class BulkUpsertUnitService
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticBulkService _elasticService;
        private readonly UpsertUnitBulkBuffer _bufferService;

        public BulkUpsertUnitService(NSCRegDbContext context, ElasticBulkService service, UpsertUnitBulkBuffer buffer)
        {
            _bufferService = buffer;
            _elasticService = service;
            _dbContext = context;
        }
        /// <summary>
        /// Creation of a local unit together with a legal unit, if there is none
        /// </summary>
        /// <param name="localUnit"></param>
        /// <returns></returns>
        public async Task CreateLocalUnit(LocalUnit localUnit)
        {
            try
            {
                _dbContext.LocalUnits.Add(localUnit);
                await _bufferService.AddToBufferAsync(localUnit);
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }

            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
        }

        /// <summary>
        /// Creating a legal unit with a local unit and an enterprise
        /// </summary>
        /// <param name="legalUnit"></param>
        /// <returns></returns>
        public async Task CreateLegalWithEnterpriseAndLocal(LegalUnit legalUnit)
        {
            EnterpriseUnit createdEnterprise = null;
            LocalUnit createdLocal = null;
            _bufferService.DisableFlushing();
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    Tracer.createStat.Start();
                    _dbContext.LegalUnits.Add(legalUnit);
                    Tracer.createStat.Stop();
                    Debug.WriteLine($"Create legal {Tracer.createStat.ElapsedMilliseconds / ++Tracer.countcreateStat}");
                    if (legalUnit.EnterpriseUnitRegId == null || legalUnit.EnterpriseUnitRegId == 0)
                    {
                        Tracer.enterprise1.Start();
                        var sameStatIdEnterprise =
                            await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(eu => eu.StatId == legalUnit.StatId);
                        Tracer.enterprise1.Stop();
                        Debug.WriteLine($"Enterprise first or default {Tracer.enterprise1.ElapsedMilliseconds / ++Tracer.countenterprise1}");

                        if (sameStatIdEnterprise != null)
                        {
                            Tracer.enterprise2.Start();
                            legalUnit.EnterpriseUnit = sameStatIdEnterprise;
                            Tracer.enterprise2.Stop();
                            Debug.WriteLine($"Enterprise link {Tracer.enterprise2.ElapsedMilliseconds / ++Tracer.countenterprise2}");
                        }
                        else
                        {
                            Tracer.enterprise3.Start();
                            createdEnterprise = await CreateEnterpriseForLegalAsync(legalUnit);
                            await _bufferService.AddToBufferAsync(createdEnterprise);
                            Tracer.enterprise3.Stop();
                            Debug.WriteLine($"Enterprise create {Tracer.enterprise3.ElapsedMilliseconds / ++Tracer.countenterprise3}");
                        }

                    }
                    Tracer.address.Start();
                    var addressIds = legalUnit.LocalUnits.Where(x => x.AddressId != null).Select(x => x.AddressId).ToList();
                    var addresses = await _dbContext.Address.Where(x => addressIds.Contains(x.Id)).ToListAsync();
                    var sameAddresses = addresses.Where(x =>
                        x.RegionId == legalUnit.Address.RegionId &&
                        x.AddressPart1 == legalUnit.Address.AddressPart1 &&
                        x.AddressPart2 == legalUnit.Address.AddressPart2 &&
                        x.AddressPart3 == legalUnit.Address.AddressPart3 &&
                        x.Latitude == legalUnit.Address.Latitude &&
                        x.Longitude == legalUnit.Address.Longitude).ToList();
                    Tracer.address.Stop();
                    Debug.WriteLine($"Address {Tracer.address.ElapsedMilliseconds / ++Tracer.countaddress}");
                    if (!sameAddresses.Any())
                    {
                        Tracer.localForLegal.Start();
                        createdLocal = await CreateLocalForLegalAsync(legalUnit);
                        await _bufferService.AddToBufferAsync(createdLocal);
                        Tracer.localForLegal.Stop();
                        Debug.WriteLine($"Local for legal create {Tracer.localForLegal.ElapsedMilliseconds / ++Tracer.countlocalForLegal}");
                    }

                    _bufferService.EnableFlushing();
                    await _bufferService.AddToBufferAsync(legalUnit);

                    //TODO: History for bulk
                    //var legalsOfEnterprise = await _dbContext.LegalUnits.Where(leu => leu.RegId == legalUnit.EnterpriseUnitRegId)
                    //    .Select(x => x.RegId).ToListAsync();
                    //legalUnit.EnterpriseUnit.HistoryLegalUnitIds += string.Join(",", legalsOfEnterprise);
                    //Tracer.commit2.Start();

                    //_dbContext.EnterpriseUnits.Update(legalUnit.EnterpriseUnit);

                    //legalUnit.HistoryLocalUnitIds = createdLocal?.RegId.ToString();
                    //_dbContext.LegalUnits.Update(legalUnit);

                    ////await _dbContext.SaveChangesAsync();
                    //Tracer.commit2.Stop();
                    //Debug.WriteLine($"History {Tracer.commit2.ElapsedMilliseconds / ++Tracer.countcommit2}");

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
            Tracer.elastic.Start();
            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(legalUnit));
            if (createdLocal != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLocal));
            if (createdEnterprise != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterprise));
            Tracer.elastic.Stop();
            Debug.WriteLine($"Elastic {Tracer.elastic.ElapsedMilliseconds / ++Tracer.countelastic}\n\n");

        }

        /// <summary>
        /// Creating an enterprise with a group of enterprises
        /// </summary>
        /// <param name="enterpriseUnit"></param>
        /// <returns></returns>
        public async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            EnterpriseGroup createdGroup = null;

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId <= 0)
                    {

                        //createdGroup = await CreateGroupForEnterpriseAsync(enterpriseUnit);
                        //await _bufferService.AddToBufferAsync(createdGroup);
                        //var sameStatIdLegalUnits = await _dbContext.LegalUnits.Where(leu => leu.StatId == enterpriseUnit.StatId).ToListAsync();
                        //foreach (var legalUnit in sameStatIdLegalUnits)
                        //{
                        //    legalUnit.EnterpriseUnit = enterpriseUnit;
                        //    _dbContext.LegalUnits.Update(legalUnit);
                        //    await _bufferService.AddToBufferAsync(legalUnit);
                        //}
                        //enterpriseUnit.HistoryLegalUnitIds = string.Join(",", sameStatIdLegalUnits.Select(x => x.RegId));

                    }
                    await _bufferService.AddToBufferAsync(enterpriseUnit);
                    //await _dbContext.SaveChangesAsync();
                    //TODO Расследовать и поменять условия Where
                    //var legalsOfEnterprise = await _dbContext.LegalUnits.Where(leu => leu.RegId == createdUnit.RegId)
                    //    .Select(x => x.RegId).ToListAsync();
                    //createdUnit.HistoryLegalUnitIds = string.Join(",", legalsOfEnterprise);

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit));
            if (createdGroup != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdGroup));
        }
        private async Task<EnterpriseUnit> CreateEnterpriseForLegalAsync(LegalUnit legalUnit)
        {
            var enterpriseUnit = new EnterpriseUnit
            {
                AddressId = legalUnit.AddressId,
                ActualAddressId = legalUnit.ActualAddressId,
            };
            Mapper.Map(legalUnit, enterpriseUnit);
            await _dbContext.EnterpriseUnits.AddAsync(enterpriseUnit);
            legalUnit.EnterpriseUnit = enterpriseUnit;

            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits, legalUnit.ForeignParticipationCountriesUnits, enterpriseUnit);

            return enterpriseUnit;
        }
        private void CreateActivitiesAndPersonsAndForeignParticipations(IEnumerable<Activity> activities, IEnumerable<PersonStatisticalUnit> persons, IEnumerable<CountryStatisticalUnit> foreignPartCountries, StatisticalUnit unit)
        {
            activities.ForEach(x =>
            {
                _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                {
                    ActivityId = x.Id,
                    Unit = unit
                });
            });
            persons.ForEach(x =>
            {
                _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                {
                    PersonId = x.PersonId,
                    Unit = unit,
                    PersonTypeId = x.PersonTypeId,
                    EnterpriseGroupId = x.EnterpriseGroupId
                });
            });

            foreignPartCountries.ForEach(x =>
            {
                _dbContext.CountryStatisticalUnits.Add(new CountryStatisticalUnit
                {
                    Unit = unit,
                    CountryId = x.CountryId
                });

            });

        }
        private async Task<LocalUnit> CreateLocalForLegalAsync(LegalUnit legalUnit)
        {
            var localUnit = new LocalUnit
            {
                AddressId = legalUnit.AddressId,
                ActualAddressId = legalUnit.ActualAddressId,
                LegalUnit = legalUnit
            };

            Mapper.Map(legalUnit, localUnit);
            await _dbContext.LocalUnits.AddAsync(localUnit);

            CreateActivitiesAndPersonsAndForeignParticipations(legalUnit.Activities, legalUnit.PersonsUnits, legalUnit.ForeignParticipationCountriesUnits, localUnit);

            return localUnit;
        }
        private async Task<EnterpriseGroup> CreateGroupForEnterpriseAsync(EnterpriseUnit enterpriseUnit)
        {
            var enterpriseGroup = new EnterpriseGroup
            {
                AddressId = enterpriseUnit.AddressId,
                ActualAddressId = enterpriseUnit.ActualAddressId,
            };

            Mapper.Map(enterpriseUnit, enterpriseGroup);
            enterpriseUnit.EnterpriseGroup = enterpriseGroup;
            await _dbContext.EnterpriseGroups.AddAsync(enterpriseGroup);

            return enterpriseGroup;
        }
    }
}
