using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Utilities.Extensions;
using System;
using System.Collections.Generic;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// Класс-помощник для создания статистических единиц по правилам
    /// </summary>
    public partial class StatUnitCreationHelper
    {
        private readonly NSCRegDbContext _dbContext;

        public StatUnitCreationHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        /// <summary>
        /// Создание локальной единицы вместе с правовой единицей, при её отсутствии
        /// </summary>
        /// <param name="localUnit"></param>
        /// <returns></returns>
        public async Task CreateLocalWithLegal(LocalUnit localUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (localUnit.LegalUnitId == null || localUnit.LegalUnitId == 0)
                    {
                        var existingLegal = _dbContext.LegalUnits.FirstOrDefault(leu => leu.StatId == localUnit.StatId);
                        var createdLocal = await CreateStatUnitAsync(localUnit);

                        if (existingLegal != null)
                            await LinkLegalToLocalAsync(existingLegal, createdLocal);
                        else
                            await CreateLegalForLocalAsync(createdLocal);
                    }
                    else
                    {
                        _dbContext.LocalUnits.Add(localUnit);
                        await _dbContext.SaveChangesAsync();
                    }

                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }

        /// <summary>
        /// Создние правовой единицы вместе с локальной единицей и предприятием
        /// </summary>
        /// <param name="legalUnit"></param>
        /// <returns></returns>
        public async Task CreateLegalWithEnterpriseAndLocal(LegalUnit legalUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (legalUnit.EnterpriseUnitRegId == null || legalUnit.EnterpriseUnitRegId == 0)
                    {
                        var sameStatIdEnterprise =
                            _dbContext.EnterpriseUnits.FirstOrDefault(eu => eu.StatId == legalUnit.StatId);
                        var sameStatIdLocalUnits =
                            _dbContext.LocalUnits.Where(lou => lou.StatId == legalUnit.StatId).ToList();
                        var createdLegal = await CreateStatUnitAsync(legalUnit);

                        if (sameStatIdEnterprise != null && sameStatIdLocalUnits.Any())
                        {
                            await LinkEnterpriseToLegalAsync(sameStatIdEnterprise, createdLegal);
                            await LinkLocalsToLegalAsync(sameStatIdLocalUnits, createdLegal);
                        }
                        else if (sameStatIdEnterprise == null && !sameStatIdLocalUnits.Any())
                        {
                            await CreateEnterpriseForLegalAsync(createdLegal);
                            await CreateLocalForLegalAsync(createdLegal);
                        }
                        else if (sameStatIdEnterprise != null && sameStatIdLocalUnits.Any())
                        {
                            await CreateLocalForLegalAsync(createdLegal);
                            await LinkEnterpriseToLegalAsync(sameStatIdEnterprise, createdLegal);
                        }
                        else if (sameStatIdEnterprise == null && sameStatIdLocalUnits.Any())
                        {
                            await CreateEnterpriseForLegalAsync(createdLegal);
                            await LinkLocalsToLegalAsync(sameStatIdLocalUnits, createdLegal);
                        }
                    }
                    else
                    {
                        _dbContext.LegalUnits.Add(legalUnit);
                        await _dbContext.SaveChangesAsync();
                    }
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }

        /// <summary>
        /// Создание предприятия с группой предприятий
        /// </summary>
        /// <param name="enterpriseUnit"></param>
        /// <returns></returns>
        public async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId == 0)
                    {
                        var createdEnterprise = await CreateStatUnitAsync(enterpriseUnit);
                        await CreateGroupForEnterpriseAsync(createdEnterprise);

                        var sameStatIdLegalUnits = _dbContext.LegalUnits.Where(leu => leu.StatId == enterpriseUnit.StatId).ToList();
                        await LinkLegalsToEnterpriseAsync(sameStatIdLegalUnits, createdEnterprise);
                    }
                    else
                    {
                        _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                        await _dbContext.SaveChangesAsync();
                    }
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }

        /// <summary>
        /// Создание группы предприятий
        /// </summary>
        /// <param name="enterpriseGroup"></param>
        /// <returns></returns>
        public async Task CreateGroup(EnterpriseGroup enterpriseGroup)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    var createdEnterpriseGroup = await CreateStatUnitAsync(enterpriseGroup);

                    var sameStatIdEnterprises = _dbContext.EnterpriseUnits.Where(eu => eu.StatId == enterpriseGroup.StatId).ToList();
                    await LinkEnterprisesToGroupAsync(sameStatIdEnterprises, createdEnterpriseGroup);
                    
                    transaction.Commit();
                }
                catch (Exception e)
                {
                    throw new BadRequestException(nameof(Resource.SaveError), e);
                }
            }
        }
    }
}
