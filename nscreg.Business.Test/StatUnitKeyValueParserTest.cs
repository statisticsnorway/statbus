using System.Collections.Generic;
using nscreg.Business.DataUpload;
using nscreg.Data.Entities;
using Xunit;
using System;
using System.Globalization;

namespace nscreg.Business.Test
{
    public class StatUnitKeyValueParserTest
    {
        [Fact]
        private void ParseStringProp()
        {
            var unit = new LocalUnit {Name = "ku"};
            const string sourceProp = "name";
            const string targetProp = nameof(unit.Name);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            const string expected = "qwerty";
            var raw = new Dictionary<string, string> {[sourceProp] = expected};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.Name);
        }

        [Fact]
        private void ParseIntProp()
        {
            var unit = new LegalUnit {NumOfPeople = 2};
            const string sourceProp = "peopleNum";
            const string targetProp = nameof(unit.NumOfPeople);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            const int expected = 17;
            var raw = new Dictionary<string, string> {[sourceProp] = expected.ToString()};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.NumOfPeople);
        }

        [Fact]
        private void ParseDateTimeProp()
        {
            var unit = new EnterpriseUnit {RegIdDate = DateTime.Now.AddDays(-5)};
            const string sourceProp = "created";
            const string targetProp = nameof(unit.RegIdDate);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            var dt = new DateTime(DateTime.Now.Ticks);
            var expected = dt.AddTicks(-dt.Ticks % TimeSpan.TicksPerSecond);
            var raw = new Dictionary<string, string> {[sourceProp] = expected.ToString(CultureInfo.InvariantCulture)};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.RegIdDate);
        }

        [Fact]
        private void ParseDecimalProp()
        {
            var unit = new EnterpriseGroup {Turnover = 0};
            const string sourceProp = "turnover";
            const string targetProp = nameof(unit.Turnover);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            const decimal expected = 17.17m;
            var raw = new Dictionary<string, string> {[sourceProp] = expected.ToString(CultureInfo.InvariantCulture)};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.Turnover);
        }

        [Fact]
        private void ParseBoolProp()
        {
            var unit = new LocalUnit {FreeEconZone = false};
            const string sourceProp = "isFreeEconZone";
            const string targetProp = nameof(unit.FreeEconZone);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            const bool expected = true;
            var raw = new Dictionary<string, string> {[sourceProp] = expected.ToString()};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.FreeEconZone);
        }

        [Fact]
        private void ParseNullableIntProp()
        {
            var unit = new LocalUnit {AddressId = 100500};
            const string sourceProp = "address_id";
            const string targetProp = nameof(unit.AddressId);
            var mapping = new Dictionary<string, string> {[sourceProp] = targetProp};
            int? expected = null;
            var raw = new Dictionary<string, string> {[sourceProp] = string.Empty};

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected, unit.AddressId);
        }

        [Fact]
        private void ParseMultipleProps()
        {
            var unit = new LegalUnit {Name = "1", NumOfPeople = 1, EmployeesDate = DateTime.Now.AddYears(-1)};
            var sourceProps = new[] {"namee", "peopleNum", "emp_date", "address_id"};
            var mapping = new Dictionary<string, string>
            {
                [sourceProps[0]] = nameof(unit.Name),
                [sourceProps[1]] = nameof(unit.NumOfPeople),
                [sourceProps[2]] = nameof(unit.EmployeesDate),
                [sourceProps[3]] = nameof(unit.AddressId),
            };
            var expected = new[]
            {
                "new name",
                100500.ToString(),
                DateTime.Now.ToString(CultureInfo.InvariantCulture),
                null,
            };
            var raw = new Dictionary<string, string>
            {
                [sourceProps[0]] = expected[0],
                [sourceProps[1]] = expected[1],
                [sourceProps[2]] = expected[2],
                [sourceProps[3]] = expected[3],
            };

            StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

            Assert.Equal(expected[0], unit.Name);
            Assert.Equal(expected[1], unit.NumOfPeople.ToString());
            Assert.Equal(expected[2], unit.EmployeesDate.ToString(CultureInfo.InvariantCulture));
            Assert.Equal(string.IsNullOrEmpty(expected[3]), !unit.AddressId.HasValue);
        }
    }
}
