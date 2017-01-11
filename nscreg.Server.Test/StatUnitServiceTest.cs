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
using Xunit;

namespace nscreg.Server.Test
{
    public class StatUnitServiceTest
    {
        private readonly NSCRegDbContext _context;
        private readonly IEnumerable<string> _propNames;
        private readonly StatUnitService _service;
        public StatUnitServiceTest()
        {
            _context = new InMemoryDb().GetContext;
            _propNames = typeof(StatisticalUnit).GetProperties().ToList().Select(x => x.Name);
            _service = new StatUnitService(_context);
        }
        #region SearchTests

        [Theory]
        [InlineData(StatUnitTypes.LegalUnit)]
        [InlineData(StatUnitTypes.LocalUnit)]
        [InlineData(StatUnitTypes.EnterpriseUnit)]
        [InlineData(StatUnitTypes.EnterpriseGroup)]
        [InlineData(StatUnitTypes.LegalUnit, true)]
        [InlineData(StatUnitTypes.LocalUnit, true)]
        [InlineData(StatUnitTypes.EnterpriseUnit, true)]
        [InlineData(StatUnitTypes.EnterpriseGroup, true)]
        public void SearchByNameOrAddressTest(StatUnitTypes unitType, bool substring = false)
        {
            var unitName = Guid.NewGuid().ToString();
            var addressPart = Guid.NewGuid().ToString();
            var address = new Address {AddressPart1 = addressPart};
            IStatisticalUnit unit;
            switch (unitType)
            {
                case StatUnitTypes.LocalUnit:
                    unit = new LocalUnit {Name = unitName, Address = address};
                    _context.LocalUnits.Add((LocalUnit) unit);
                    break;
                case StatUnitTypes.LegalUnit:
                    unit = new LegalUnit {Name = unitName, Address = address};
                    _context.LegalUnits.Add((LegalUnit) unit);
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    unit = new EnterpriseUnit {Name = unitName, Address = address};
                    _context.EnterpriseUnits.Add((EnterpriseUnit) unit);
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    unit = new EnterpriseGroup {Name = unitName, Address = address};
                    _context.EnterpriseGroups.Add((EnterpriseGroup) unit);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(unitType), unitType, null);
            }
            _context.SaveChanges();

            #region ByName

            var query = new SearchQueryM {Wildcard = substring ? unitName.Remove(unitName.Length - 1) : unitName};
            var result = _service.Search(query, _propNames);
            Assert.Equal(1, result.TotalCount);

            #endregion

            #region ByAddress

            query = new SearchQueryM {Wildcard = substring ? addressPart.Remove(addressPart.Length - 1) : addressPart};
            result = _service.Search(query, _propNames);
            Assert.Equal(1, result.TotalCount);

            #endregion
    }

        [Fact]
        public void SearchByNameMultiplyResultTest()
        {
            var commonName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = commonName + Guid.NewGuid()};
            var local = new LocalUnit() {Name = Guid.NewGuid() + commonName + Guid.NewGuid()};
            var enterprise = new EnterpriseUnit() {Name = Guid.NewGuid() + commonName};
            var group = new EnterpriseGroup() {Name = Guid.NewGuid() + commonName};
            {
                _context.LegalUnits.Add(legal);
                _context.LocalUnits.Add(local);
                _context.EnterpriseUnits.Add(enterprise);
                _context.EnterpriseGroups.Add(group);
                _context.SaveChanges();
                var query = new SearchQueryM {Wildcard = commonName};

                var result = _service.Search(query, _propNames);

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
            var unitName = Guid.NewGuid().ToString();
            var legal = new LegalUnit {Name = unitName};
            var local = new LocalUnit {Name = unitName};
            var enterprise = new EnterpriseUnit {Name = unitName};
            var group = new EnterpriseGroup() {Name = unitName};
                _context.LegalUnits.Add(legal);
                _context.LocalUnits.Add(local);
                _context.EnterpriseUnits.Add(enterprise);
                _context.EnterpriseGroups.Add(group);
                _context.SaveChanges();
                var query = new SearchQueryM
                {
                    Wildcard = unitName,
                    Type = type,
                };

                var result = _service.Search(query, _propNames);

                Assert.Equal(1, result.TotalCount);
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
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        _service.CreateLegalUnit(new LegalUnitCreateM {Name = unitName, Address = address});
                        Assert.IsType<LegalUnit>(
                            _context.LegalUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            _service.CreateLegalUnit(new LegalUnitCreateM {Name = unitName, Address = address});
                        }
                        catch (Exception e)
                        {
                            actual = e.GetType();
                        }
                        Assert.Equal(expected, actual);
                        break;
                    case StatUnitTypes.LocalUnit:
                        _service.CreateLocalUnit(new LocalUnitCreateM {Name = unitName, Address = address});
                        Assert.IsType<LocalUnit>(
                            _context.LocalUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            _service.CreateLocalUnit(new LocalUnitCreateM() {Name = unitName, Address = address});
                        }
                        catch (Exception e)
                        {
                            actual = e.GetType();
                        }
                        Assert.Equal(expected, actual);
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        _service.CreateEnterpriseUnit(new EnterpriseUnitCreateM {Name = unitName, Address = address});
                        Assert.IsType<EnterpriseUnit>(
                            _context.EnterpriseUnits.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            _service.CreateEnterpriseUnit(new EnterpriseUnitCreateM {Name = unitName, Address = address});
                        }
                        catch (Exception e)
                        {
                            actual = e.GetType();
                        }
                        Assert.Equal(expected, actual);
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        _service.CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM()
                        {
                            Name = unitName,
                            Address = address
                        });
                        Assert.IsType<EnterpriseGroup>(
                            _context.EnterpriseGroups.Single(
                                x =>
                                    x.Name == unitName && x.Address.AddressPart1 == address.AddressPart1 && !x.IsDeleted));
                        try
                        {
                            _service.CreateEnterpriseGroupUnit(new EnterpriseGroupCreateM()
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
                int unitId;
                var expected = typeof(BadRequestException);
                Type actual = null;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        _context.LegalUnits.AddRange(new List<LegalUnit>
                        {
                            new LegalUnit {Name = unitName},
                            new LegalUnit
                            {
                                Name = dublicateName,
                                Address = new Address {AddressPart1 = addressPartOne}
                            }
                        });
                        _context.SaveChanges();
                        unitId = _context.LegalUnits.Single(x => x.Name == unitName).RegId;
                        _service.EditLegalUnit(new LegalUnitEditM {RegId = unitId, Name = unitNameEdit});
                        Assert.IsType<LegalUnit>(
                            _context.LegalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        try
                        {
                            _service.EditLegalUnit(new LegalUnitEditM
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
                        _context.LocalUnits.AddRange(new List<LocalUnit>
                        {
                            new LocalUnit {Name = unitName},
                            new LocalUnit
                            {
                                Name = dublicateName,
                                Address = new Address {AddressPart1 = addressPartOne}
                            }
                        });
                        _context.SaveChanges();
                        unitId = _context.LocalUnits.Single(x => x.Name == unitName).RegId;
                        _service.EditLocalUnit(new LocalUnitEditM {RegId = unitId, Name = unitNameEdit});
                        Assert.IsType<LocalUnit>(
                            _context.LocalUnits.Single(x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        try
                        {
                            _service.EditLocalUnit(new LocalUnitEditM
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
                        _context.EnterpriseUnits.AddRange(new List<EnterpriseUnit>
                        {
                            new EnterpriseUnit {Name = unitName},
                            new EnterpriseUnit
                            {
                                Name = dublicateName,
                                Address = new Address {AddressPart1 = addressPartOne}
                            }
                        });
                        _context.SaveChanges();
                        unitId = _context.EnterpriseUnits.Single(x => x.Name == unitName).RegId;
                        _service.EditEnterpiseUnit(new EnterpriseUnitEditM {RegId = unitId, Name = unitNameEdit});
                        Assert.IsType<EnterpriseUnit>(
                            _context.EnterpriseUnits.Single(
                                x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        try
                        {
                            _service.EditEnterpiseUnit(new EnterpriseUnitEditM()
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
                        _context.EnterpriseGroups.AddRange(new List<EnterpriseGroup>
                        {
                            new EnterpriseGroup {Name = unitName},
                            new EnterpriseGroup
                            {
                                Name = dublicateName,
                                Address = new Address {AddressPart1 = addressPartOne}
                            }
                        });
                        _context.SaveChanges();
                        unitId = _context.EnterpriseGroups.Single(x => x.Name == unitName).RegId;
                        _service.EditEnterpiseGroup(new EnterpriseGroupEditM {RegId = unitId, Name = unitNameEdit});
                        Assert.IsType<EnterpriseGroup>(
                            _context.EnterpriseGroups.Single(
                                x => x.RegId == unitId && x.Name == unitNameEdit && !x.IsDeleted));
                        try
                        {
                            _service.EditEnterpiseGroup(new EnterpriseGroupEditM
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
                var unitName = Guid.NewGuid().ToString();
                int unitId;
                switch (type)
                {
                    case StatUnitTypes.LegalUnit:
                        _context.LegalUnits.Add(new LegalUnit {Name = unitName, IsDeleted = false});
                        _context.SaveChanges();
                        unitId = _context.LegalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        _service.DeleteUndelete(type, unitId, true);
                        Assert.IsType<LegalUnit>(_context.LegalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        break;
                    case StatUnitTypes.LocalUnit:
                        _context.LocalUnits.Add(new LocalUnit {Name = unitName, IsDeleted = false});
                        _context.SaveChanges();
                        unitId = _context.LocalUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        _service.DeleteUndelete(type, unitId, true);
                        Assert.IsType<LocalUnit>(_context.LocalUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        break;
                    case StatUnitTypes.EnterpriseUnit:
                        _context.EnterpriseUnits.Add(new EnterpriseUnit {Name = unitName, IsDeleted = false});
                        _context.SaveChanges();
                        unitId = _context.EnterpriseUnits.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        _service.DeleteUndelete(type, unitId, true);
                        Assert.IsType<EnterpriseUnit>(
                            _context.EnterpriseUnits.Single(x => x.Name == unitName && x.IsDeleted));
                        break;
                    case StatUnitTypes.EnterpriseGroup:
                        _context.EnterpriseGroups.Add(new EnterpriseGroup {Name = unitName, IsDeleted = false});
                        _context.SaveChanges();
                        unitId = _context.EnterpriseGroups.Single(x => x.Name == unitName && !x.IsDeleted).RegId;
                        _service.DeleteUndelete(type, unitId, true);
                        Assert.IsType<EnterpriseGroup>(
                            _context.EnterpriseGroups.Single(x => x.Name == unitName && x.IsDeleted));
                        break;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(type), type, null);
                }
            }

        #endregion
    }
}