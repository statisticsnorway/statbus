using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using System.Threading.Tasks;
using System;
using AutoMapper;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// Helper class for creating statistical units by rules
    /// </summary>
    public partial class StatUnitCreationHelper
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticService _elasticService;

        public StatUnitCreationHelper(NSCRegDbContext dbContext, ElasticService service)
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
                    createdLegal = await CreateStatUnitAsync(legalUnit);

                    if (legalUnit.EnterpriseUnitRegId == null || legalUnit.EnterpriseUnitRegId == 0)
                    {
                        var sameStatIdEnterprise =
                            _dbContext.EnterpriseUnits.FirstOrDefault(eu => eu.StatId == legalUnit.StatId);

                        if (sameStatIdEnterprise != null)
                            await LinkEnterpriseToLegalAsync(sameStatIdEnterprise, createdLegal);
                        else
                            createdEnterprise = await CreateEnterpriseForLegalAsync(createdLegal);
                    }

                    var addressIds = legalUnit.LocalUnits.Where(x => x.AddressId != null).Select(x => x.AddressId).ToList();
                    var addresses = _dbContext.Address.Where(x => addressIds.Contains(x.Id)).ToList();
                    var sameAddresses = addresses.Where(x =>
                        x.RegionId == legalUnit.Address.RegionId &&
                        x.AddressPart1 == legalUnit.Address.AddressPart1 &&
                        x.AddressPart2 == legalUnit.Address.AddressPart2 &&
                        x.AddressPart3 == legalUnit.Address.AddressPart3 &&
                        x.Latitude == legalUnit.Address.Latitude &&
                        x.Longitude == legalUnit.Address.Longitude).ToList();
                    if (!sameAddresses.Any())
                        createdLocal = await CreateLocalForLegalAsync(createdLegal);

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }

            await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLegal));
            if(createdLocal != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLocal));
            if (createdEnterprise != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterprise));
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
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId == 0)
                    {
                        createdUnit = await CreateStatUnitAsync(enterpriseUnit);
                        createdGroup = await CreateGroupForEnterpriseAsync(createdUnit);

                        var sameStatIdLegalUnits = _dbContext.LegalUnits.Where(leu => leu.StatId == enterpriseUnit.StatId).ToList();
                        await LinkLegalsToEnterpriseAsync(sameStatIdLegalUnits, createdUnit);
                    }
                    else
                    {
                        createdUnit = _dbContext.EnterpriseUnits.Add(enterpriseUnit).Entity;
                        await _dbContext.SaveChangesAsync();
                    }
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
                    await LinkEnterprisesToGroupAsync(sameStatIdEnterprises, createdEnterpriseGroup);

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
