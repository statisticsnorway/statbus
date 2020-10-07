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
        /// <param name="legal"></param>
        /// <returns></returns>
        public async Task CreateLegalWithEnterpriseAndLocal(LegalUnit legal)
        {
            _bufferService.DisableFlushing();
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    Tracer.createStat.Start();
                    Tracer.createStat.Stop();
                    Debug.WriteLine($"Create legal {Tracer.createStat.ElapsedMilliseconds / ++Tracer.countcreateStat}");
                    if (legal.EnterpriseUnitRegId == null || legal.EnterpriseUnitRegId == 0)
                    {
                        Tracer.enterprise1.Start();
                        var sameStatIdEnterprise =
                            await _dbContext.EnterpriseUnits.FirstOrDefaultAsync(eu => eu.StatId == legal.StatId);
                        Tracer.enterprise1.Stop();
                        Debug.WriteLine(
                            $"Enterprise first or default {Tracer.enterprise1.ElapsedMilliseconds / ++Tracer.countenterprise1}");

                        if (sameStatIdEnterprise != null)
                        {
                            Tracer.enterprise2.Start();
                            legal.EnterpriseUnit = sameStatIdEnterprise;
                            Tracer.enterprise2.Stop();
                            Debug.WriteLine(
                                $"Enterprise link {Tracer.enterprise2.ElapsedMilliseconds / ++Tracer.countenterprise2}");
                        }
                        else
                        {
                            Tracer.enterprise3.Start();
                            CreateEnterpriseForLegal(legal);
                            Tracer.enterprise3.Stop();
                            Debug.WriteLine(
                                $"Enterprise create {Tracer.enterprise3.ElapsedMilliseconds / ++Tracer.countenterprise3}");
                        }
                        await _bufferService.AddToBufferAsync(legal.EnterpriseUnit);

                    }

                    Tracer.address.Start();
                    const double tolerance = 0.000000001;
                    var addressIds = legal.LocalUnits.Where(x => x.AddressId != null).Select(x => x.AddressId).ToList();
                    var addresses = await _dbContext.Address.Where(x => addressIds.Contains(x.Id) && x.RegionId == legal.Address.RegionId &&
                                                                        x.AddressPart1 == legal.Address.AddressPart1 &&
                                                                        x.AddressPart2 == legal.Address.AddressPart2 &&
                                                                        x.AddressPart3 == legal.Address.AddressPart3 && legal.Address.Latitude != null && Math.Abs((double)x.Latitude - (double)legal.Address.Latitude) < tolerance && legal.Address.Longitude != null && Math.Abs((double)x.Longitude - (double)legal.Address.Longitude) < tolerance).ToListAsync();
                    Tracer.address.Stop();
                    Debug.WriteLine($"Address {Tracer.address.ElapsedMilliseconds / ++Tracer.countaddress}");
                    if (!addresses.Any())
                    {
                        Tracer.localForLegal.Start();
                        CreateLocalForLegal(legal);
                        await _bufferService.AddToBufferAsync(legal.LocalUnits.Last());
                        Tracer.localForLegal.Stop();
                        Debug.WriteLine(
                            $"Local for legal create {Tracer.localForLegal.ElapsedMilliseconds / ++Tracer.countlocalForLegal}");
                    }

                    _bufferService.EnableFlushing();
                    await _bufferService.AddToBufferAsync(legal);

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

                //TODO: Вынести во Flush потому что некоторые поля до Flush null и не присвоены
                //Tracer.elastic.Start();
                //await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(legal));
                //if (createdLocal != null)
                //    await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdLocal));
                //if (createdEnterprise != null)
                //    await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(createdEnterprise));
                //Tracer.elastic.Stop();
                //Debug.WriteLine($"Elastic {Tracer.elastic.ElapsedMilliseconds / ++Tracer.countelastic}\n\n");

            }

        }

        /// <summary>
        /// Creating an enterprise with a group of enterprises
        /// </summary>
        /// <param name = "enterpriseUnit" ></param >
        /// < returns ></returns >
        public async Task CreateEnterpriseWithGroup(EnterpriseUnit enterpriseUnit)
        {
            using (var transaction = _dbContext.Database.BeginTransaction())
            {
                try
                {
                    _dbContext.EnterpriseUnits.Add(enterpriseUnit);
                    if (enterpriseUnit.EntGroupId == null || enterpriseUnit.EntGroupId <= 0)
                    {

                        CreateGroupForEnterpriseAsync(enterpriseUnit);
                        var sameStatIdLegalUnits = await _dbContext.LegalUnits.Where(leu => leu.StatId == enterpriseUnit.StatId).ToListAsync();
                        foreach (var legalUnit in sameStatIdLegalUnits)
                        {
                            legalUnit.EnterpriseUnit = enterpriseUnit;
                        }
                        enterpriseUnit.HistoryLegalUnitIds = string.Join(",", sameStatIdLegalUnits.Select(x => x.RegId));

                    }
                    //await _bufferService.AddLegalToBufferAsync(enterpriseUnit);
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
            if (enterpriseUnit.EnterpriseGroup != null)
                await _elasticService.AddDocument(Mapper.Map<IStatisticalUnit, ElasticStatUnit>(enterpriseUnit.EnterpriseGroup));
        }


        private void CreateEnterpriseForLegal(LegalUnit legalUnit)
        {
            var enterpriseUnit = new EnterpriseUnit();
            Mapper.Map(legalUnit, enterpriseUnit);
            legalUnit.EnterpriseUnit = enterpriseUnit;
        }
        private void CreateLocalForLegal(LegalUnit legalUnit)
        {
            var localUnit = new LocalUnit();
            Mapper.Map(legalUnit, localUnit);
            legalUnit.LocalUnits.Add(localUnit);
        }
        private void CreateGroupForEnterpriseAsync(EnterpriseUnit enterpriseUnit)
        {
            var enterpriseGroup = new EnterpriseGroup();
            Mapper.Map(enterpriseUnit, enterpriseGroup);
            enterpriseUnit.EnterpriseGroup = enterpriseGroup;
        }
    }
}
