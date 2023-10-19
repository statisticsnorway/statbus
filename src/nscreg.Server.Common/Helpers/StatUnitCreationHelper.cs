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
        private readonly IMapper _mapper;

        public StatUnitCreationHelper(NSCRegDbContext dbContext, IElasticUpsertService service, IMapper mapper)
        {
            _dbContext = dbContext;
            _elasticService = service;
            _mapper = mapper;
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

            await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(localUnit));
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
                    createdLegal = await CreateStatUnitAsync(legalUnit);
                    await _dbContext.SaveChangesAsync();
                    if (legalUnit.EnterpriseUnitRegId == null || legalUnit.EnterpriseUnitRegId == 0)
                    {
                        var sameStatIdEnterprise =
                            await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(eu => eu.StatId == legalUnit.StatId);

                        if (sameStatIdEnterprise != null)
                        {
                            createdLegal.EnterpriseUnit = sameStatIdEnterprise;
                        }
                        else
                        {
                            createdEnterprise = await CreateEnterpriseForLegalAsync(createdLegal);
                        }
                    }

                    var addressIds = legalUnit.LocalUnits.Where(x => x.ActualAddressId != null).Select(x => x.ActualAddressId).ToList();
                    var addresses = await _dbContext.Address.Where(x => addressIds.Contains(x.Id)).ToListAsync();
                    var sameAddresses = addresses.Where(x =>
                        x.RegionId == legalUnit.ActualAddress.RegionId &&
                        x.AddressPart1 == legalUnit.ActualAddress.AddressPart1 &&
                        x.AddressPart2 == legalUnit.ActualAddress.AddressPart2 &&
                        x.AddressPart3 == legalUnit.ActualAddress.AddressPart3 &&
                        x.Latitude == legalUnit.ActualAddress.Latitude &&
                        x.Longitude == legalUnit.ActualAddress.Longitude).ToList();
                    
                    if (!sameAddresses.Any())
                    {
                        createdLocal = await CreateLocalForLegalAsync(createdLegal);
                    }
                    await _dbContext.SaveChangesAsync();

                    var regId = legalUnit.EnterpriseUnitRegId ??= createdEnterprise.RegId;
                    var legalsOfEnterprise = await _dbContext.LegalUnits.Where(leu => leu.EnterpriseUnitRegId == regId)
                        .Select(x => x.RegId).ToListAsync();

                    if(createdLegal.EnterpriseUnit == null)
                        createdLegal.EnterpriseUnit = await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(x => x.RegId == regId);

                    createdLegal.EnterpriseUnit.HistoryLegalUnitIds += string.Join(",", legalsOfEnterprise);
                    
                    _dbContext.EnterpriseUnits.Update(createdLegal.EnterpriseUnit);

                    createdLegal.HistoryLocalUnitIds = createdLocal?.RegId.ToString();
                    _dbContext.LegalUnits.Update(createdLegal);

                    await _dbContext.SaveChangesAsync();

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
            Tracer.elastic.Start();
            await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLegal));
            if(createdLocal != null)
               await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLocal));
            if (createdEnterprise != null)
                await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterprise));
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

            await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdUnit));
            if(createdGroup != null)
                await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdGroup));
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

            await _elasticService.AddDocument(_mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterpriseGroup));
        }
        public async Task CheckElasticConnect()
        {
            await _elasticService.CheckElasticSearchConnection();
        }
    }
}
