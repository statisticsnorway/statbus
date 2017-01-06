using System;
using System.Collections.Generic;
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
        #region SearchTests


        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.LegalUnit, true)]
        [InlineData(StatUnitTypes.LocalUnit, true)]
        [InlineData(StatUnitTypes.EnterpriseUnit, true)]
        public void SearchByNameOrAddressTest(StatUnitTypes unitType, bool substring = false)
        {
            var unitName = Guid.NewGuid().ToString();
            var addressPart = Guid.NewGuid().ToString();
            var address = new Address {AddressPart1 = addressPart};
            var context = new InMemoryDb().GetContext;
            IStatisticalUnit unit;
            switch (unitType)
            {
                case StatUnitTypes.LocalUnit:
                    unit = new LocalUnit {Name = unitName, Address = address};
                    context.LocalUnits.Add((LocalUnit) unit);
                    break;
                case StatUnitTypes.LegalUnit:
                    unit = new LegalUnit {Name = unitName, Address = address};
                    context.LegalUnits.Add((LegalUnit) unit);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unit = new EnterpriseUnit {Name = unitName, Address = address};
                    context.EnterpriseUnits.Add((EnterpriseUnit) unit);
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    unit = new EnterpriseGroup {Name = unitName, Address = address};
                    context.EnterpriseGroups.Add((EnterpriseGroup) unit);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(unitType), unitType, null);
            }
            context.SaveChanges();
            var propNames = typeof(StatisticalUnit).GetProperties().ToList();
            var service = new StatUnitService(context);

            #region ByName

            var query = new SearchQueryM {Wildcard = substring ? unitName.Remove(unitName.Length - 1) : unitName};
            var result = service.Search(query, propNames.Select(x => x.Name));
            Assert.Equal(1, result.TotalCount);

            #endregion

            #region ByAddress

            query = new SearchQueryM {Wildcard = substring ? addressPart.Remove(addressPart.Length - 1) : addressPart};
            result = service.Search(query, propNames.Select(x => x.Name));
            Assert.Equal(1, result.TotalCount);

            #endregion

            context.Dispose();
        }

        [Fact]
        public void SearchByNameMultiplyResultTest()
        {
            var commonName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = commonName + Guid.NewGuid()};
            var local = new LocalUnit() {Name = Guid.NewGuid() + commonName + Guid.NewGuid()};
            var enterprise = new EnterpriseUnit() {Name = Guid.NewGuid() + commonName};
            using (var context = new InMemoryDb().GetContext)
            {
                context.LegalUnits.Add(legal);
                context.LocalUnits.Add(local);
                context.EnterpriseUnits.Add(enterprise);
                context.SaveChanges();
                var propNames = typeof(StatisticalUnit).GetProperties().ToList();
                var service = new StatUnitService(context);
                var query = new SearchQueryM {Wildcard = commonName};

                var result = service.Search(query, propNames.Select(x => x.Name));

                Assert.Equal(3, result.TotalCount);
            }
        }

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        public void SearchUsingUnitTypeTest(StatUnitTypes type)
        {
            var unitName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = unitName};
            var local = new LocalUnit {Name = unitName};
            var enterprise = new EnterpriseUnit {Name = unitName};
            using (var context = new InMemoryDb().GetContext)
            {
                context.LegalUnits.Add(legal);
                context.LocalUnits.Add(local);
                context.EnterpriseUnits.Add(enterprise);
                context.SaveChanges();
                var propNames = typeof(StatisticalUnit).GetProperties().ToList();
                var service = new StatUnitService(context);
                var query = new SearchQueryM
                {
                    Wildcard = unitName,
                    Type = type,
                };

                var result = service.Search(query, propNames.Select(x => x.Name));

                Assert.Equal(1, result.TotalCount);
            }
        }

        #endregion

        #region CreateTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void CreateTest(StatUnitTypes type)
        {
            AutoMapperConfiguration.Configure();
            var context = new InMemoryDb().GetContext;
            var unitName = Guid.NewGuid().ToString();
            var address = new AddressM {AddressPart1 = Guid.NewGuid().ToString()};
            var service = new StatUnitService(context);
            var expected = typeof(BadRequestException);
            Type actual = null;
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    service.CreateLegalUnit(new LegalUnitCreateM {Name = unitName, Address = address});
                    Assert.IsType<LegalUnit>(
                        context.LegalUnits.Single(
                            x => x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                    try
                    {
                        service.CreateLegalUnit(new LegalUnitCreateM {Name = unitName, Address = address});
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.LocalUnit:
                    service.CreateLocalUnit(new LocalUnitCreateM {Name = unitName, Address = address});
                    Assert.IsType<LocalUnit>(
                        context.LocalUnits.Single(
                            x => x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                    try
                    {
                        service.CreateLocalUnit(new LocalUnitCreateM() {Name = unitName, Address = address});
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    service.CreateEnterpriseUnit(new EnterpriseUnitCreateM {Name = unitName, Address = address});
                    Assert.IsType<EnterpriseUnit>(
                        context.EnterpriseUnits.Single(
                            x => x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                    try
                    {
                        service.CreateEnterpriseUnit(new EnterpriseUnitCreateM {Name = unitName, Address = address});
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    service.CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM() {Name = unitName, Address = address});
                    Assert.IsType<EnterpriseGroup>(
                        context.EnterpriseGroups.Single(
                            x => x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                    try
                    {
                        service.CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM()
                        {
                            Name = unitName,
                            Address = address
                        });
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        #endregion

        #region EditTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void EditTest(StatUnitTypes type)
        {
            AutoMapperConfiguration.Configure();
            var unitName = Guid.NewGuid().ToString();
            var unitNameEdit = Guid.NewGuid().ToString();
            var dublicateName = Guid.NewGuid().ToString();
            var addressPartOne = Guid.NewGuid().ToString();
            var context = new InMemoryDb().GetContext;
            var service = new StatUnitService(context);
            int unitId;
            var expected = typeof(BadRequestException);
            Type actual = null;
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    context.LegalUnits.AddRange(new List<LegalUnit>
                    {
                        new LegalUnit {Name = unitName},
                        new LegalUnit
                        {
                            Name = dublicateName,
                            Address = new Address {AddressPart1 = addressPartOne}
                        }
                    });
                    context.SaveChanges();
                    unitId = context.LegalUnits.Single(x => x.Name == unitName).RegId;
                    service.EditLegalUnit(new LegalUnitEditM {RegId = unitId, Name = unitNameEdit});
                    Assert.IsType<LegalUnit>(
                        context.LegalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    try
                    {
                        service.EditLegalUnit(new LegalUnitEditM
                        {
                            RegId = unitId,
                            Name = dublicateName,
                            Address = new AddressM {AddressPart1 = addressPartOne}
                        });
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.LocalUnit:
                    context.LocalUnits.AddRange(new List<LocalUnit>
                    {
                        new LocalUnit {Name = unitName},
                        new LocalUnit
                        {
                            Name = dublicateName,
                            Address = new Address {AddressPart1 = addressPartOne}
                        }
                    });
                    context.SaveChanges();
                    unitId = context.LocalUnits.Single(x => x.Name == unitName).RegId;
                    service.EditLocalUnit(new LocalUnitEditM {RegId = unitId, Name = unitNameEdit});
                    Assert.IsType<LocalUnit>(
                        context.LocalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    try
                    {
                        service.EditLocalUnit(new LocalUnitEditM
                        {
                            RegId = unitId,
                            Name = dublicateName,
                            Address = new AddressM {AddressPart1 = addressPartOne}
                        });
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    context.EnterpriseUnits.AddRange(new List<EnterpriseUnit>
                    {
                        new EnterpriseUnit {Name = unitName},
                        new EnterpriseUnit
                        {
                            Name = dublicateName,
                            Address = new Address {AddressPart1 = addressPartOne}
                        }
                    });
                    context.SaveChanges();
                    unitId = context.EnterpriseUnits.Single(x => x.Name == unitName).RegId;
                    service.EditEnterpiseUnit(new EnterpriseUnitEditM {RegId = unitId, Name = unitNameEdit});
                    Assert.IsType<EnterpriseUnit>(
                        context.EnterpriseUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    try
                    {
                        service.EditEnterpiseUnit(new EnterpriseUnitEditM()
                        {
                            RegId = unitId,
                            Name = dublicateName,
                            Address = new AddressM {AddressPart1 = addressPartOne}
                        });
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    context.EnterpriseGroups.AddRange(new List<EnterpriseGroup>
                    {
                        new EnterpriseGroup {Name = unitName},
                        new EnterpriseGroup
                        {
                            Name = dublicateName,
                            Address = new Address {AddressPart1 = addressPartOne}
                        }
                    });
                    context.SaveChanges();
                    unitId = context.EnterpriseGroups.Single(x => x.Name == unitName).RegId;
                    service.EditEnterpiseGroup(new EnterpriseGroupEditM {RegId = unitId, Name = unitNameEdit});
                    Assert.IsType<EnterpriseGroup>(
                        context.EnterpriseGroups.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                    try
                    {
                        service.EditEnterpiseGroup(new EnterpriseGroupEditM
                        {
                            RegId = unitId,
                            Name = dublicateName,
                            Address = new AddressM {AddressPart1 = addressPartOne}
                        });
                    }
                    catch (Exception e)
                    {
                        actual = e.GetType();
                    }
                    Assert.Equal(expected, actual);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        #endregion

        #region DeleteTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void DeleteTest(StatUnitTypes type)
        {
            AutoMapperConfiguration.Configure();
            var context = new InMemoryDb().GetContext;
            var service = new StatUnitService(context);
            var unitName = Guid.NewGuid().ToString();
            int unitId;
            switch (type)
            {
                case StatUnitTypes.LegalUnit:
                    context.LegalUnits.Add(new LegalUnit {Name = unitName, IsDeleted = false});
                    context.SaveChanges();
                    unitId = context.LegalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                    service.DeleteUndelete(type, unitId, true);
                    Assert.IsType<LegalUnit>(context.LegalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                    break;
                case StatUnitTypes.LocalUnit:
                    context.LocalUnits.Add(new LocalUnit {Name = unitName, IsDeleted = false});
                    context.SaveChanges();
                    unitId = context.LocalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                    service.DeleteUndelete(type, unitId, true);
                    Assert.IsType<LocalUnit>(context.LocalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    context.EnterpriseUnits.Add(new EnterpriseUnit {Name = unitName, IsDeleted = false});
                    context.SaveChanges();
                    unitId = context.EnterpriseUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                    service.DeleteUndelete(type, unitId, true);
                    Assert.IsType<EnterpriseUnit>(context.EnterpriseUnits.Single(x => x.Name == unitName && x.IsDeleted));
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    context.EnterpriseGroups.Add(new EnterpriseGroup {Name = unitName, IsDeleted = false});
                    context.SaveChanges();
                    unitId = context.EnterpriseGroups.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                    service.DeleteUndelete(type, unitId, true);
                    Assert.IsType<EnterpriseGroup>(
                        context.EnterpriseGroups.Single(x => x.Name == unitName && x.IsDeleted));
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        #endregion
    }
}