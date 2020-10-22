using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using System.Threading.Tasks;
using System;
using System.Diagnostics;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Helpers
{
    public static class Tracer
    {
        public static Stopwatch createStat = new Stopwatch();
        public static Stopwatch enterprise1 = new Stopwatch();
        public static Stopwatch enterprise2 = new Stopwatch();
        public static Stopwatch enterprise3 = new Stopwatch();
        public static Stopwatch address = new Stopwatch();
        public static Stopwatch localForLegal = new Stopwatch();
        public static Stopwatch commit = new Stopwatch();
        public static Stopwatch commit2 = new Stopwatch();
        public static Stopwatch elastic = new Stopwatch();

        public static int countcreateStat;
        public static int countenterprise1;
        public static int countenterprise2;
        public static int countenterprise3;
        public static int countaddress;
        public static int countlocalForLegal;
        public static int countcommit;
        public static int countcommit2;
        public static int countelastic;
    }
    /// <summary>
    /// Helper class for creating statistical units by rules
    /// </summary>
    public partial class StatUnitCreationHelper
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly IElasticUpsertService _elasticService;

        public StatUnitCreationHelper(NSCRegDbContext dbContext, IElasticUpsertService service)
        {
            _dbContext = dbContext;
            _elasticService = service;
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
                await _dbContext.SaveChangesAsync();
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
            LegalUnit createdLegal;
            EnterpriseUnit createdEnterprise = null;
            LocalUnit createdLocal = null;
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    Tracer.createStat.Start();
                    createdLegal = await CreateStatUnitAsync(legalUnit);
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
                            createdLegal.EnterpriseUnit = sameStatIdEnterprise;
                            Tracer.enterprise2.Stop();
                            Debug.WriteLine($"Enterprise link {Tracer.enterprise2.ElapsedMilliseconds / ++Tracer.countenterprise2}");
                        }
                        else
                        {
                            Tracer.enterprise3.Start();
                            createdEnterprise = await CreateEnterpriseForLegalAsync(createdLegal);
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
                        createdLocal = await CreateLocalForLegalAsync(createdLegal);
                        Tracer.localForLegal.Stop();
                        Debug.WriteLine($"Local for legal create {Tracer.localForLegal.ElapsedMilliseconds / ++Tracer.countlocalForLegal}");
                    }

                    Tracer.commit.Start();
                    await _dbContext.SaveChangesAsync();
                    Tracer.commit.Stop();
                    Debug.WriteLine($"CREATE ALL ENTITIES {Tracer.commit.ElapsedMilliseconds / ++Tracer.countcommit}");

                    var legalsOfEnterprise = await _dbContext.LegalUnits.Where(leu => leu.RegId == createdLegal.EnterpriseUnitRegId)
                        .Select(x => x.RegId).ToListAsync();
                    createdLegal.EnterpriseUnit.HistoryLegalUnitIds += string.Join(",", legalsOfEnterprise);
                    Tracer.commit2.Start();
                    
                    _dbContext.EnterpriseUnits.Update(createdLegal.EnterpriseUnit);

                    createdLegal.HistoryLocalUnitIds = createdLocal?.RegId.ToString();
                    _dbContext.LegalUnits.Update(createdLegal);

                    await _dbContext.SaveChangesAsync();
                    Tracer.commit2.Stop();
                    Debug.WriteLine($"History {Tracer.commit2.ElapsedMilliseconds / ++Tracer.countcommit2}");

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
            Tracer.elastic.Start();
            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLegal));
            if(createdLocal != null)
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
            EnterpriseUnit createdUnit;
            EnterpriseGroup createdGroup = null;

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    createdUnit = await CreateStatUnitAsync(enterpriseUnit);
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId <= 0)
                    {
                        
                        createdGroup = await CreateGroupForEnterpriseAsync(createdUnit);

                        var sameStatIdLegalUnits = await _dbContext.LegalUnits.Where(leu => leu.StatId == enterpriseUnit.StatId).ToListAsync();
                        foreach (var legalUnit in sameStatIdLegalUnits)
                        {
                            legalUnit.EnterpriseUnit = enterpriseUnit;
                            _dbContext.LegalUnits.Update(legalUnit);
                        }
                        createdUnit.HistoryLegalUnitIds = string.Join(",", sameStatIdLegalUnits.Select(x=>x.RegId));

                    }
                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdUnit));
            if(createdGroup != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdGroup));
        }

        /// <summary>
        /// Creation of a group of enterprises
        /// </summary>
        /// <param name="enterpriseGroup"></param>
        /// <returns></returns>
        public async Task CreateGroup(EnterpriseGroup enterpriseGroup)
        {
            EnterpriseGroup createdEnterpriseGroup;

            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    createdEnterpriseGroup = await CreateStatUnitAsync(enterpriseGroup);

                    var sameStatIdEnterprises = _dbContext.EnterpriseUnits.Where(eu => eu.StatId == enterpriseGroup.StatId).ToList();
                    foreach (var enterpriseUnit in sameStatIdEnterprises)
                    {
                        enterpriseUnit.EnterpriseGroup = enterpriseGroup;
                        _dbContext.EnterpriseUnits.Update(enterpriseUnit);
                    }

                    await  _dbContext.SaveChangesAsync();

                    
                    var enterprisesOfGroup = _dbContext.EnterpriseUnits.Where(eu => eu.RegId == enterpriseGroup.RegId)
                        .Select(x => x.RegId).ToList();
                    enterpriseGroup.HistoryEnterpriseUnitIds = string.Join(",", enterprisesOfGroup);
                    _dbContext.Update(enterpriseGroup);
                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterpriseGroup));
        }
        public async Task CheckElasticConnect()
        {
            await _elasticService.CheckElasticSearchConnection();
        }
    }
}
