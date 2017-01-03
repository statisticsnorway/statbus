using System;
using System.Linq;
using System.Reflection;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Core;
using nscreg.Server.Models;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;
using Xunit;

namespace nscreg.Server.Test
{
    public class StatUnitServiceTest
    {

        [Theory]
        [InlineData((int)StatUnitTypes.LegalUnit)]
        [InlineData((int)StatUnitTypes.LocalUnit)]
        [InlineData((int)StatUnitTypes.EnterpriseUnit)]
        //[InlineData((int)StatUnitTypes.EnterpriseGroup)]
        [InlineData((int)StatUnitTypes.LegalUnit, 10)]
        [InlineData((int)StatUnitTypes.LocalUnit, 10)]
        [InlineData((int)StatUnitTypes.EnterpriseUnit, 10)]
        //[InlineData((int)StatUnitTypes.EnterpriseGroup, 10)]
        public void SearchByNameOrAddressTest(int unitType, int substring = 0)
        {
            var unitName = Guid.NewGuid().ToString();
            var addressPart = Guid.NewGuid().ToString();
            var address = new Address {AddressPart1 = addressPart};
            var context = new InMemoryDb().GetContext;
            IStatisticalUnit unit;
            switch (unitType)
            {
                case 1:
                    unit = new LocalUnit { Name = unitName, Address = address };
                    context.LocalUnits.Add((LocalUnit)unit);
                    break;
                case 2:
                    unit = new LegalUnit { Name = unitName, Address = address };
                    context.LegalUnits.Add((LegalUnit)unit);
                    break;
                case 3:
                    unit = new EnterpriseUnit { Name = unitName, Address = address };
                    context.EnterpriseUnits.Add((EnterpriseUnit)unit);
                    break;
                case 4:
                    unit = new EnterpriseGroup { Name = unitName, Address = address };
                    context.EnterpriseGroups.Add((EnterpriseGroup)unit);
                    break;
                default:
                    Assert.True(false);
                    break;
            }
            context.SaveChanges();
            var propNames = typeof(StatisticalUnit).GetProperties().ToList();
            var service = new StatUnitService(context);

            #region ByName
            var query = new SearchQueryM { Wildcard = (substring > 0) ? unitName.Substring(substring, unitName.Length - substring) : unitName };
            var result = service.Search(query, propNames.Select(x => x.Name));
            Assert.True(result.TotalCount == 1);
            #endregion

            #region ByAddress
            query = new SearchQueryM { Wildcard = (substring > 0) ? addressPart.Substring(substring, addressPart.Length - substring) : addressPart };
            result = service.Search(query, propNames.Select(x => x.Name));
            Assert.True(result.TotalCount == 1);
            #endregion

            context.Dispose();
        }

        [Fact]
        public void SearchByNameMultiplyResultTest()
        {
            var commonName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = commonName+Guid.NewGuid()};
            var local = new LocalUnit() {Name = Guid.NewGuid()+commonName+Guid.NewGuid()};
            var enterprise = new EnterpriseUnit() {Name = Guid.NewGuid()+commonName};
            var context = new InMemoryDb().GetContext;
            context.LegalUnits.Add(legal);
            context.LocalUnits.Add(local);
            context.EnterpriseUnits.Add(enterprise);
            context.SaveChanges();
            var propNames = typeof(StatisticalUnit).GetProperties().ToList();
            var service = new StatUnitService(context);
            var query = new SearchQueryM { Wildcard = commonName };
            var result = service.Search(query, propNames.Select(x => x.Name));
            Assert.Equal(3, result.TotalCount);
            context.Dispose();
        }

        [Fact]
        public void SearchUsingUnitTypeTest()
        {
            var unitName = Guid.NewGuid().ToString();
            var legal = new LegalUnit { Name = unitName };
            var local = new LocalUnit { Name = unitName };
            var enterprise = new EnterpriseUnit { Name = unitName };
            var context = new InMemoryDb().GetContext;
            context.LegalUnits.Add(legal);
            context.LocalUnits.Add(local);
            context.EnterpriseUnits.Add(enterprise);
            context.SaveChanges();
            var propNames = typeof(StatisticalUnit).GetProperties().ToList();
            var service = new StatUnitService(context);
            var query = new SearchQueryM
            {
                Wildcard = unitName,
                Type = StatUnitTypes.LegalUnit,
            };
            var result = service.Search(query, propNames.Select(x => x.Name));
            Assert.Equal(1, result.TotalCount);
            context.Dispose();
        }

        [Fact]
        public void CreateEditDeleteTest()
        {
            AutoMapperConfiguration.Configure();
            var unitName = Guid.NewGuid().ToString();
            var dublicatedName = Guid.NewGuid().ToString();
            var context = new InMemoryDb().GetContext;
            var service = new StatUnitService(context);
            var createAddress = new AddressM {AddressPart1 = Guid.NewGuid().ToString()};
            var createData = new LegalUnitCreateM {Name = unitName, Address = createAddress };
            var dublicatedData = new LegalUnitCreateM {Name = dublicatedName, Address = createAddress };
            //Create Assert
            service.CreateLegalUnit(createData);
            service.CreateLegalUnit(dublicatedData);
            //Dublicate while create check Assert
            var expected = typeof(BadRequestException);
            Type actual = null;
            try
            {
                service.CreateLegalUnit(dublicatedData);
            }
            catch (Exception e)
            {
                actual = e.GetType();
            }
            Assert.Equal(expected, actual);
            //Edit Assert
            var unit = context.LegalUnits.Single(x => x.Name == unitName && x.Address.AddressPart1 == createAddress.AddressPart1 && !x.IsDeleted);
            unitName = Guid.NewGuid().ToString();
            service.EditLegalUnit(new LegalUnitEditM {RegId = unit.RegId, Name = unitName, Address = createAddress});
            unit = context.LegalUnits.Single(x => x.Name == unitName && x.Address.AddressPart1 == createAddress.AddressPart1 && !x.IsDeleted);
            //Dublicate detected whyle updated
            actual = null;
            try
            {
                service.EditLegalUnit(new LegalUnitEditM
                {
                    RegId = unit.RegId,
                    Name = dublicatedName,
                    Address = createAddress
                });
            }
            catch (Exception e)
            {
                actual = e.GetType();
            }
            Assert.Equal(expected, actual);
            //Delete Assert
            service.DeleteUndelete(StatUnitTypes.LegalUnit, unit.RegId, true);
            Assert.IsType<LegalUnit>(context.LegalUnits.Single(x => x.Name == unitName && x.Address.AddressPart1 == createAddress.AddressPart1 && x.IsDeleted));
            context.Dispose();
        }
    }
}