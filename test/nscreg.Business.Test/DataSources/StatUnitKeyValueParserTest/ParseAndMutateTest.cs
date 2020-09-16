using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using nscreg.TestUtils;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using Xunit;

namespace nscreg.Business.Test.DataSources.StatUnitKeyValueParserTest
{
    public class ParseAndMutateTest
    {
        //[Fact]
        //private void ParseStringProp()
        //{
        //    var unit = new LocalUnit {Name = "ku"};
        //    const string sourceProp = "name";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.Name)}};
        //    const string expected = "qwerty";
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.Name);
        //}

        //[Fact]
        //private void ParseIntProp()
        //{
        //    var unit = new LegalUnit {NumOfPeopleEmp = 2};
        //    const string sourceProp = "peopleNum";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.NumOfPeopleEmp)}};
        //    const int expected = 17;
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected.ToString()};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.NumOfPeopleEmp);
        //}

        //[Fact]
        //private void ParseDateTimeProp()
        //{
        //    var unit = new EnterpriseUnit {RegIdDate = DateTime.Now.AddDays(-5)};
        //    const string sourceProp = "created";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.RegIdDate)}};
        //    var expected = DateTime.Now.FlushSeconds();
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected.ToString(CultureInfo.InvariantCulture)};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.RegIdDate);
        //}

        //[Fact]
        //private void ParseDecimalProp()
        //{
        //    var unit = new EnterpriseUnit {Turnover = 0};
        //    const string sourceProp = "turnover";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.Turnover)}};
        //    const decimal expected = 17.17m;
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected.ToString(CultureInfo.InvariantCulture)};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.Turnover);
        //}

        //[Fact]
        //private void ParseBoolProp()
        //{
        //    var unit = new LocalUnit {FreeEconZone = false};
        //    const string sourceProp = "isFreeEconZone";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.FreeEconZone)}};
        //    const bool expected = true;
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected.ToString()};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.FreeEconZone);
        //}

        //[Fact]
        //private void ParseNullableIntProp()
        //{
        //    var unit = new LocalUnit {AddressId = 100500};
        //    const string sourceProp = "address_id";
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {nameof(unit.AddressId)}};
        //    int? expected = null;
        //    var raw = new Dictionary<string, object> {[sourceProp] = string.Empty};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.AddressId);
        //}

        //[Fact]
        //private void ParseMultipleProps()
        //{
        //    var unit = new LegalUnit {Name = "1", NumOfPeopleEmp = 1, EmployeesDate = DateTime.Now.AddYears(-1)};
        //    var sourceProps = new[] {"namee", "peopleNum", "emp_date", "address_id"};
        //    var mapping = new Dictionary<string, string[]>
        //    {
        //        [sourceProps[0]] = new[] {nameof(unit.Name)},
        //        [sourceProps[1]] = new[] {nameof(unit.NumOfPeopleEmp)},
        //        [sourceProps[2]] = new[] {nameof(unit.EmployeesDate)},
        //        [sourceProps[3]] = new[] {nameof(unit.AddressId)},
        //    };
        //    var expected = new[]
        //    {
        //        "new name",
        //        100500.ToString(),
        //        DateTime.Now.ToString(CultureInfo.InvariantCulture),
        //        "1",
        //    };
        //    var raw = new Dictionary<string, object>
        //    {
        //        [sourceProps[0]] = expected[0],
        //        [sourceProps[1]] = expected[1],
        //        [sourceProps[2]] = expected[2],
        //        [sourceProps[3]] = expected[3],
        //    };

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected[0], unit.Name);
        //    Assert.Equal(expected[1], unit.NumOfPeopleEmp.ToString());
        //    Assert.Equal(expected[2], unit.EmployeesDate?.ToString(CultureInfo.InvariantCulture));
        //    Assert.Equal(string.IsNullOrEmpty(expected[3]), !unit.AddressId.HasValue);
        //}

        //[Fact]
        //private void ParseIfNotMappedPropIsIgnored()
        //{
        //    const string expected = "some name";
        //    var unit = new LocalUnit {Name = expected};
        //    var mapping = new Dictionary<string, string[]>();
        //    var raw = new Dictionary<string, object> {["emptyNotes"] = nameof(unit.Notes)};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expected, unit.Name);
        //}

        //[Fact]
        //private void ParseWithStringToNullableIntMapping()
        //{
        //    var unit = new EnterpriseUnit();
        //    const string sourceProp = "sourceProp";
        //    var mapping = new Dictionary<string, string[]>
        //    {
        //        [sourceProp] = new[] {nameof(StatisticalUnit.InstSectorCodeId)}
        //    };

        //    const int expected = 42;
        //    var raw = new Dictionary<string, object> {[sourceProp] = "42"};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.InstSectorCodeId);
        //    Assert.Equal(expected, unit.InstSectorCodeId.Value);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForActivities()
        //{
        //    const string value = "01.11.9";
        //    var expected = new List<KeyValuePair<string, Dictionary<string, string>>> { (new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string> { { "Code", value } })) };
        //    const string sourceProp = "Activities";
        //    var propPath =
        //        $"{nameof(StatisticalUnit.Activities)}.{nameof(Activity.ActivityCategory)}.{nameof(ActivityCategory.Code)}";
        //    var unit = new LegalUnit();
        //    var mapping = new Dictionary<string, string[]> {["Activities.Activity.Code"] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.Activities);
        //    Assert.NotEmpty(unit.Activities);
        //    Assert.NotNull(unit.Activities.First());
        //    Assert.NotNull(unit.Activities.First().ActivityCategory);
        //    Assert.Equal(value, unit.Activities.First().ActivityCategory.Code);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForAddress()
        //{
        //    const string expected = "some", sourceProp = "address";
        //    var propPath = $"{nameof(StatisticalUnit.Address)}.{nameof(Address.Region)}.{nameof(Region.Code)}";
        //    var unit = new LegalUnit();
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.Address);
        //    Assert.NotNull(unit.Address.Region);
        //    Assert.Equal(expected, unit.Address.Region.Code);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForActualAddress()
        //{
        //    const string expected = "some", sourceProp = "actualAddress";
        //    var propPath = $"{nameof(StatisticalUnit.ActualAddress)}.{nameof(Address.Region)}.{nameof(Region.Code)}";
        //    var unit = new LegalUnit();
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.ActualAddress);
        //    Assert.NotNull(unit.ActualAddress.Region);
        //    Assert.Equal(expected, unit.ActualAddress.Region.Code);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForInstSectorCode()
        //{
        //    const string expected = "some", sourceProp = "instSectorCode";
        //    var propPath = $"{nameof(StatisticalUnit.InstSectorCode)}.{nameof(SectorCode.Code)}";
        //    var unit = new LocalUnit();
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.InstSectorCode);
        //    Assert.Equal(expected, unit.InstSectorCode.Code);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForLegalForm()
        //{
        //    const string expected = "some", sourceProp = "legalForm";
        //    var propPath = $"{nameof(StatisticalUnit.LegalForm)}.{nameof(LegalForm.Code)}";
        //    var unit = new LocalUnit();
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {[sourceProp] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.LegalForm);
        //    Assert.Equal(expected, unit.LegalForm.Code);
        //}

        //[Fact]
        //private void ParseComplexFieldShouldPassForPersons()
        //{
        //    var expected = new List<KeyValuePair<string, Dictionary<string, string>>>{(new KeyValuePair<string,Dictionary<string,string>>("Person",new Dictionary<string, string>{{"Name","MyName"}}))};
        //    const string sourceProp = "Persons.Person.Name";
        //    var propPath = $"{nameof(StatisticalUnit.Persons)}.{nameof(Person)}.{nameof(Person.GivenName)}";
        //    var unit = new LegalUnit();
        //    var mapping = new Dictionary<string, string[]> {[sourceProp] = new[] {propPath}};
        //    var raw = new Dictionary<string, object> {["Persons"] = expected};

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.NotNull(unit.Persons);
        //    Assert.NotEmpty(unit.Persons);
        //    Assert.NotNull(unit.Persons.First());
        //}

        //[Fact]
        //private void ParseMultipleFieldsFromOneSourceAttribute()
        //{
        //    const string source = "source", expectedName = "name";
        //    var unit = new LocalUnit();
        //    var mapping = new Dictionary<string, string[]>
        //    {
        //        [source] = new[] {nameof(unit.Name), nameof(unit.ShortName)},
        //    };
        //    var raw = new Dictionary<string, object>
        //    {
        //        [source] = expectedName,
        //    };

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Equal(expectedName, unit.Name);
        //    Assert.Equal(expectedName, unit.ShortName);
        //}

        //[Fact]
        //private void ParseMultipleFieldsOnFromOneSourceAttributeForComplexEntitiesInList()
        //{
        //    const string source = "Persons";
        //    const string nameValue = "MyName";
        //    var expected = new List<KeyValuePair<string, Dictionary<string, string>>> { (new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string> { { "Name", nameValue } })) };
        //    var unit = new LegalUnit();
        //    var mapping = new Dictionary<string, string[]>
        //    {
        //        ["Persons.Person.Name"] = new[]
        //        {
        //            $"{nameof(unit.Persons)}.{nameof(Person.GivenName)}",
        //            $"{nameof(unit.Persons)}.{nameof(Person.Surname)}"
        //        },
        //    };
        //    var raw = new Dictionary<string, object>
        //    {
        //        [source] = expected,
        //    };

        //    StatUnitKeyValueParser.ParseAndMutateStatUnit(mapping, raw, unit);

        //    Assert.Single(unit.Persons);
        //    Assert.Equal(nameValue, unit.Persons.First().GivenName);
        //    Assert.Equal(nameValue, unit.Persons.First().Surname);
        //}
    }
}
