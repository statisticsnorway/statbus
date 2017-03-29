using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Core;
using nscreg.Server.Models;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;
using nscreg.Server.Test.Extensions;
using Xunit;
using static nscreg.Server.Test.InMemoryDb;

namespace nscreg.Server.Test
{
    public class StatUnitServiceTest
    {
        private readonly IEnumerable<string> _propNames;

        public StatUnitServiceTest()
        {
            _propNames = typeof(StatisticalUnit).GetProperties().ToList().Select(x => x.Name);
        }

        #region SearchTests

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void SearchByNameOrAddressTest(StatUnitTypes unitType)
        {
            var unitName = Guid.NewGuid().ToString();
            var addressPart = Guid.NewGuid().ToString();
            var address = new Address {AddressPart1 = addressPart};
            using (var context = CreateContext())
            {
                context.Initialize();
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

                var statUnit =
                    context.StatisticalUnits.FirstOrDefault(
                        x => x.UnitType == unitType && x.UnitType != StatUnitTypes.EnterpriseGroup);

                #region ByName

                var query = new SearchQueryM {Wildcard = unitName.Remove(unitName.Length - 1)};
                var result = new StatUnitService(context).Search(query, DbContextExtensions.UserId);
                Assert.Equal(1, result.TotalCount);

                #endregion

                #region ByAddress

                query = new SearchQueryM {Wildcard = addressPart.Remove(addressPart.Length - 1)};
                result = new StatUnitService(context).Search(query, DbContextExtensions.UserId);
                Assert.Equal(1, result.TotalCount);

                #endregion
            }
        }

        [Fact]
        public void SearchByNameMultiplyResultTest()
        {
            var commonName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = commonName + Guid.NewGuid()};
            var local = new LocalUnit {Name = Guid.NewGuid() + commonName + Guid.NewGuid()};
            var enterprise = new EnterpriseUnit {Name = Guid.NewGuid() + commonName};
            var group = new EnterpriseGroup {Name = Guid.NewGuid() + commonName};
            using (var context = CreateContext())
            {
                context.Initialize();
                context.LegalUnits.Add(legal);
                context.LocalUnits.Add(local);
                context.EnterpriseUnits.Add(enterprise);
                context.EnterpriseGroups.Add(group);
                context.SaveChanges();

                foreach (var type in Enum.GetValues(typeof(StatUnitTypes)))
                {
                    var unit =
                        context.StatisticalUnits.FirstOrDefault(
                            x => x.UnitType == (StatUnitTypes) type && x.UnitType != StatUnitTypes.EnterpriseGroup);
                }

                var query = new SearchQueryM {Wildcard = commonName};
                var result = new StatUnitService(context).Search(query, DbContextExtensions.UserId);

                Assert.Equal(4, result.TotalCount);
            }
        }

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void SearchUsingUnitTypeTest(StatUnitTypes type)
        {
            using (var context = CreateContext())
            {
                context.Initialize();
                var unitName = Guid.NewGuid().ToString();
                var legal = new LegalUnit {Name = unitName};
                var local = new LocalUnit {Name = unitName};
                var enterprise = new EnterpriseUnit {Name = unitName};
                var group = new EnterpriseGroup {Name = unitName};
                context.LegalUnits.Add(legal);
                context.LocalUnits.Add(local);
                context.EnterpriseUnits.Add(enterprise);
                context.EnterpriseGroups.Add(group);
                context.SaveChanges();

                var unit =
                    context.StatisticalUnits.FirstOrDefault(
                        x => x.UnitType == type && x.UnitType != StatUnitTypes.EnterpriseGroup);

                var query = new SearchQueryM
                {
                    Wildcard = unitName,
                    Type = type
                };

                var result = new StatUnitService(context).Search(query, DbContextExtensions.UserId);

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
            var unitName = Guid.NewGuid().ToString();
            var address = new AddressM {AddressPart1 = Guid.NewGuid().ToString()};
            var expected = typeof(BadRequestException);
            Type actual = null;
            using (var context = CreateContext())
            {
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        new StatUnitService(context).CreateLegalUnit(new LegalUnitCreateM
                        {
                            Name = unitName,
                            Address = address
                        });

                        Assert.IsType<LegalUnit>(
                            context.LegalUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            new StatUnitService(context).CreateLegalUnit(new LegalUnitCreateM
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
                    case StatUnitTypes.LocalUnit:
                        new StatUnitService(context).CreateLocalUnit(new LocalUnitCreateM
                        {
                            Name = unitName,
                            Address = address
                        });

                        Assert.IsType<LocalUnit>(
                            context.LocalUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            new StatUnitService(context).CreateLocalUnit(new LocalUnitCreateM
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
                    case StatUnitTypes.EnterpriseUnit:
                        new StatUnitService(context).CreateEnterpriseUnit(new EnterpriseUnitCreateM
                        {
                            Name = unitName,
                            Address = address
                        });

                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            new StatUnitService(context).CreateEnterpriseUnit(new EnterpriseUnitCreateM
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
                    case StatUnitTypes.EnterpriseGroup:
                        new StatUnitService(context).CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM
                        {
                            Name = unitName,
                            Address = address
                        });
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            new StatUnitService(context).CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM
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

            int unitId;
            var expected = typeof(BadRequestException);
            Type actual = null;
            using (var context = CreateContext())
            {

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

                        new StatUnitService(context).EditLegalUnit(new LegalUnitEditM
                        {
                            RegId = unitId,
                            Name = unitNameEdit,
                        }, DbContextExtensions.UserId);
                        Assert.IsType<LegalUnit>(
                            context.LegalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        Assert.IsType<LegalUnit>(
                            context.LegalUnits.Single(
                                x => x.RegId != unitId && x.ParrentId == unitId && x.Name == unitName));
                        try
                        {
                            new StatUnitService(context).EditLegalUnit(new LegalUnitEditM
                            {
                                RegId = unitId,
                                Name = dublicateName,
                                Address = new AddressM {AddressPart1 = addressPartOne}
                            },DbContextExtensions.UserId);
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
                        new StatUnitService(context).EditLocalUnit(new LocalUnitEditM
                        {
                            RegId = unitId,
                            Name = unitNameEdit,
                        });
                        Assert.IsType<LocalUnit>(
                            context.LocalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        Assert.IsType<LocalUnit>(
                            context.LocalUnits.Single(
                                x => x.RegId != unitId && x.ParrentId == unitId && x.Name == unitName));
                        try
                        {
                            new StatUnitService(context).EditLocalUnit(new LocalUnitEditM
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
                        new StatUnitService(context).EditEnterpiseUnit(new EnterpriseUnitEditM
                        {
                            RegId = unitId,
                            Name = unitNameEdit,
                        });
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(
                                x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(
                                x => x.RegId != unitId && x.ParrentId == unitId && x.Name == unitName));
                        try
                        {
                            new StatUnitService(context).EditEnterpiseUnit(new EnterpriseUnitEditM
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
                                Address = new Address {AddressPart1 = addressPartOne},
                                EnterpriseUnits = new List<EnterpriseUnit>
                                {
                                    new EnterpriseUnit {Name = unitName},
                                }
                            }
                        });
                        context.SaveChanges();

                        unitId = context.EnterpriseGroups.Single(x => x.Name == unitName).RegId;
                        new StatUnitService(context).EditEnterpiseGroup(new EnterpriseGroupEditM
                        {
                            RegId = unitId,
                            Name = unitNameEdit,
                            EnterpriseUnits = new[]
                            {
                                context.EnterpriseGroups
                                    .Where(x => x.Name == dublicateName)
                                    .Select(x => x.EnterpriseUnits).FirstOrDefault()
                                    .Where(x => x.Name == unitName)
                                    .Select(x => x.RegId).FirstOrDefault()
                            }
                        });
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(
                                x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(
                                x => x.RegId != unitId && x.ParrentId == unitId && x.Name == unitName));
                        try
                        {
                            new StatUnitService(context).EditEnterpiseGroup(new EnterpriseGroupEditM
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
            var unitName = Guid.NewGuid().ToString();
            using (var context = CreateContext())
            {
                int unitId;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        context.LegalUnits.Add(new LegalUnit {Name = unitName, IsDeleted = false});
                        context.SaveChanges();
                        unitId = context.LegalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, true);
                        Assert.IsType<LegalUnit>(context.LegalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<LegalUnit>(
                            context.LegalUnits.Single(x => x.Name == unitName && !x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.LocalUnit:
                        context.LocalUnits.Add(new LocalUnit {Name = unitName, IsDeleted = false});
                        context.SaveChanges();
                        unitId = context.LocalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, true);
                        Assert.IsType<LocalUnit>(context.LocalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<LocalUnit>(
                            context.LocalUnits.Single(x => x.Name == unitName && !x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        context.EnterpriseUnits.Add(new EnterpriseUnit {Name = unitName, IsDeleted = false});
                        context.SaveChanges();
                        unitId = context.EnterpriseUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, true);
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(
                                x => x.Name == unitName && !x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        context.EnterpriseGroups.Add(new EnterpriseGroup {Name = unitName, IsDeleted = false});
                        context.SaveChanges();
                        unitId = context.EnterpriseGroups.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, true);
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(x => x.Name == unitName && x.IsDeleted));
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(
                                x => x.Name == unitName && !x.IsDeleted && x.ParrentId == unitId));
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(type), type, null);
                }
            }
        }

        #endregion

        #region UndeleteTest

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        public void UndeleteTest(StatUnitTypes type)
        {
            AutoMapperConfiguration.Configure();
            var unitName = Guid.NewGuid().ToString();
            using (var context = CreateContext())
            {
                int unitId;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        context.LegalUnits.Add(new LegalUnit {Name = unitName, IsDeleted = true});
                        context.SaveChanges();
                        unitId = context.LegalUnits.Single(x => x.Name == unitName && x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, false);
                        Assert.IsType<LegalUnit>(context.LegalUnits.Single(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<LegalUnit>(
                            context.LegalUnits.Single(x => x.Name == unitName && x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.LocalUnit:
                        context.LocalUnits.Add(new LocalUnit {Name = unitName, IsDeleted = true});
                        context.SaveChanges();
                        unitId = context.LocalUnits.Single(x => x.Name == unitName && x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, false);
                        Assert.IsType<LocalUnit>(context.LocalUnits.Single(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<LocalUnit>(
                            context.LocalUnits.Single(x => x.Name == unitName && x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        context.EnterpriseUnits.Add(new EnterpriseUnit {Name = unitName, IsDeleted = true});
                        context.SaveChanges();
                        unitId = context.EnterpriseUnits.Single(x => x.Name == unitName && x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, false);
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<EnterpriseUnit>(
                            context.EnterpriseUnits.Single(
                                x => x.Name == unitName && x.IsDeleted && x.ParrentId == unitId));
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        context.EnterpriseGroups.Add(new EnterpriseGroup {Name = unitName, IsDeleted = true});
                        context.SaveChanges();
                        unitId = context.EnterpriseGroups.Single(x => x.Name == unitName && x.IsDeleted).RegId;
                        new StatUnitService(context).DeleteUndelete(type, unitId, false);
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(x => x.Name == unitName && !x.IsDeleted));
                        Assert.IsType<EnterpriseGroup>(
                            context.EnterpriseGroups.Single(
                                x => x.Name == unitName && x.IsDeleted && x.ParrentId == unitId));
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(type), type, null);
                }
            }
        }

        #endregion
    }
}
