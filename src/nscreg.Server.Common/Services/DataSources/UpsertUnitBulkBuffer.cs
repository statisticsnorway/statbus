using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using EFCore.BulkExtensions;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Common.Services.DataSources
{
    ///TODO продумать логику и создавать разные коллекции сущностей и разные bulkInsert
    public class UpsertUnitBulkBuffer
    {
        private bool _isEnabledFlush = true;
        private List<LegalUnit> LegalUnitsBuffer { get; }
        private List<LocalUnit> LocalUnitsBuffer { get; }
        private List<EnterpriseUnit> EnterpriseUnitsBuffer { get; }
        private readonly NSCRegDbContext _context;
        private const int MaxBulkOperationsBufferedCount = 300;
        private readonly BulkConfig _config;

        public UpsertUnitBulkBuffer(NSCRegDbContext context)
        {
            _config = new BulkConfig() { PreserveInsertOrder = true, SetOutputIdentity = true };
            LegalUnitsBuffer = new List<LegalUnit>();
            LocalUnitsBuffer = new List<LocalUnit>();
            EnterpriseUnitsBuffer = new List<EnterpriseUnit>();
            _context = context;
        }

        public async Task AddLegalToBufferAsync(LegalUnit unit)
        {
            LegalUnitsBuffer.Add(unit);
            if (LegalUnitsBuffer.Count >= MaxBulkOperationsBufferedCount && _isEnabledFlush)
            {
                await FlushLegalUnitsAsync();
            }
            
        }

        public async Task FlushLegalUnitsAsync()
        {
            //TODO : Решить проблему с Edit и HistoryIds
            //TODO: Тщательно перепроверить логику, Activities Persons, Вынести сюда же
            var addresses = LegalUnitsBuffer.SelectMany(x => new List<Address>{x.Address, x.ActualAddress, x.PostalAddress}).Where(x => x != null).ToList();
            var activities = LegalUnitsBuffer.SelectMany(x => x.Activities).ToList();
            var enterpriseUnits = LegalUnitsBuffer.Select(x => x.EnterpriseUnit).ToList();
            var localUnits = LegalUnitsBuffer.SelectMany(x => x.LocalUnits).ToList();

            await _context.BulkInsertAsync(addresses, _config);
            await _context.BulkInsertOrUpdateAsync(activities, _config);
            foreach (var unit in LegalUnitsBuffer)
            {
                unit.ActualAddressId = unit.ActualAddress?.Id;
                unit.AddressId = unit.Address?.Id;
                unit.PostalAddressId = unit.PostalAddress?.Id;
                unit.EnterpriseUnit.ActualAddressId = unit.ActualAddress?.Id;
                unit.EnterpriseUnit.AddressId = unit.Address?.Id;
                unit.EnterpriseUnit.PostalAddressId = unit.PostalAddress?.Id;
                unit.LocalUnits.ForEach(x =>
                {
                    x.ActualAddressId = unit.ActualAddress?.Id;
                    x.AddressId = unit.Address?.Id;
                    x.PostalAddressId = unit.PostalAddress?.Id;
                });
            }
            await _context.BulkInsertAsync(enterpriseUnits, _config);
            LegalUnitsBuffer.ForEach(x => x.EnterpriseUnitRegId = x.EnterpriseUnit.RegId);
            await _context.BulkInsertOrUpdateAsync(LegalUnitsBuffer, _config);
            LegalUnitsBuffer.ForEach(x => x.LocalUnits.ForEach(z => z.LegalUnitId = x.RegId));
            await _context.BulkInsertAsync(localUnits, _config);

            LegalUnitsBuffer.Clear();
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
