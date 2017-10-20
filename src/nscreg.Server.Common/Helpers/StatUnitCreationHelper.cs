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
    public partial class StatUnitCreationHelper
    {
        private readonly NSCRegDbContext _dbContext;

        public StatUnitCreationHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task CreateLocalWithLegal(LocalUnit localUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (localUnit.LegalUnitId == null || localUnit.LegalUnitId == 0)
                    {
                        var existingLegal = _dbContext.LegalUnits.FirstOrDefault(leu => leu.StatId == localUnit.StatId);
                        if (existingLegal != null)
                        {
                            localUnit.LegalUnitId = existingLegal.RegId;
                            _dbContext.LocalUnits.Add(localUnit);
                            await _dbContext.SaveChangesAsync();

                            existingLegal.HistoryLocalUnitIds += "," + localUnit.RegId;
                            _dbContext.LegalUnits.Update(existingLegal);

                            await _dbContext.SaveChangesAsync();
                        }
                        else
                        {
                            // Create corresponding legal unit
                            var legalUnit = new LegalUnit();
                            Mapper.Map(localUnit, legalUnit);

                            if ((localUnit.AddressId == 0 || localUnit.AddressId == null) && localUnit.Address != null)
                            {
                                var address = _dbContext.Address.Add(localUnit.Address).Entity;
                                await _dbContext.SaveChangesAsync();

                                localUnit.AddressId = address.Id;
                                legalUnit.AddressId = address.Id;
                            }
                            if ((localUnit.ActualAddressId == 0 || localUnit.ActualAddressId == null) &&
                                localUnit.ActualAddress != null)
                            {
                                var actualAddress = _dbContext.Address.Add(localUnit.ActualAddress).Entity;
                                await _dbContext.SaveChangesAsync();

                                localUnit.ActualAddressId = actualAddress.Id;
                                legalUnit.ActualAddressId = actualAddress.Id;
                            }

                            _dbContext.LegalUnits.Add(legalUnit);

                            // Create new activities and persons
                            localUnit.Activities.ForEach(x => { _dbContext.Activities.Add(x); });
                            localUnit.Persons.Where(x => x.Id == 0).ForEach(x => { _dbContext.Persons.Add(x); });
                            await _dbContext.SaveChangesAsync();

                            localUnit.LegalUnitId = legalUnit.RegId;
                            _dbContext.LocalUnits.Add(localUnit);
                            await _dbContext.SaveChangesAsync();

                            // Reference legal unit to local unit's activities and persons
                            localUnit.Activities.ForEach(x =>
                            {
                                _dbContext.ActivityStatisticalUnits.Add(new ActivityStatisticalUnit
                                {
                                    ActivityId = x.Id,
                                    UnitId = legalUnit.RegId
                                });
                            });
                            localUnit.Persons.ForEach(x =>
                            {
                                _dbContext.PersonStatisticalUnits.Add(new PersonStatisticalUnit
                                {
                                    PersonId = x.Id,
                                    UnitId = legalUnit.RegId,
                                    PersonType = x.Role
                                });
                            });
                            legalUnit.HistoryLocalUnitIds = localUnit.RegId.ToString();
                            _dbContext.LegalUnits.Update(legalUnit);

                            await _dbContext.SaveChangesAsync();
                        }
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
                            await LinkLocalToLegalAsync(sameStatIdLocalUnits, createdLegal);
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
                            await LinkLocalToLegalAsync(sameStatIdLocalUnits, createdLegal);
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
        
        public async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId == 0)
                    {
                        var enterpriseGroup = new EnterpriseGroup();
                        Mapper.Map(enterpriseUnit, enterpriseGroup);

                        if ((enterpriseUnit.AddressId == 0 || enterpriseUnit.AddressId == null) &&
                            enterpriseUnit.Address != null)
                        {
                            var address = _dbContext.Address.Add(enterpriseUnit.Address).Entity;
                            await _dbContext.SaveChangesAsync();

                            enterpriseUnit.AddressId = address.Id;
                            enterpriseGroup.AddressId = address.Id;
                        }

                        if ((enterpriseUnit.ActualAddressId == 0 || enterpriseUnit.ActualAddressId == null) &&
                            enterpriseUnit.ActualAddress != null)
                        {
                            var actualAddress = _dbContext.Address.Add(enterpriseUnit.ActualAddress).Entity;
                            await _dbContext.SaveChangesAsync();

                            enterpriseUnit.ActualAddressId = actualAddress.Id;
                            enterpriseGroup.ActualAddressId = actualAddress.Id;
                        }

                        _dbContext.EnterpriseGroups.Add(enterpriseGroup);

                        enterpriseUnit.Activities.ForEach(x => { _dbContext.Activities.Add(x); });
                        enterpriseUnit.Persons.Where(x => x.Id == 0).ForEach(x => { _dbContext.Persons.Add(x); });
                        await _dbContext.SaveChangesAsync();

                        enterpriseUnit.EntGroupId = enterpriseGroup.RegId;
                        _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                        await _dbContext.SaveChangesAsync();

                        enterpriseGroup.HistoryEnterpriseUnitIds = enterpriseUnit.RegId.ToString();
                        _dbContext.EnterpriseGroups.Update(enterpriseGroup);

                        await _dbContext.SaveChangesAsync();
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

        public async Task CreateGroup(EnterpriseGroup enterpriseGroup)
        {
            _dbContext.EnterpriseGroups.Add(enterpriseGroup);
            try
            {
                await _dbContext.SaveChangesAsync();
            }
            catch (Exception e)
            {
                throw new BadRequestException(nameof(Resource.SaveError), e);
            }
        }
    }
}
