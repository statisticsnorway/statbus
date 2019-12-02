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
    /// Класс-помощник для создания статистических единиц по правилам
    /// </summary>
    public partial class StatUnitCreationHelper
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly ElasticService _elasticService;

        public StatUnitCreationHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _elasticService = new ElasticService(dbContext);
        }

        /// <summary>
        /// Создание локальной единицы вместе с правовой единицей, при её отсутствии
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
        /// Создние правовой единицы вместе с локальной единицей и предприятием
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

                    var sameStatIdLocalUnits =
                        _dbContext.LocalUnits.Where(lou => lou.StatId == legalUnit.StatId).ToList();

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
        /// Создание предприятия с группой предприятий
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
        /// Создание группы предприятий
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
