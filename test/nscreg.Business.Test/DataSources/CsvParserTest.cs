using System.Collections.Generic;
using System.Linq;
using FluentAssertions;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources
{
    public class CsvParserTest
    {
        [Theory]
        [InlineData(
            "StatId;StatUnitName;parent_unit;organistaional_form;RegisterDate;dateOfCommencement;dateChangeOfOwner\n"
            + "919228741;ALEX TRANSPORT;919018828;BEDR;2017-07-03;2017-06-04;\n"
            + "919228768;UNISOL UTEGLASS AS;919146605;BEDR;;;\n"
            + "919228776;PETBNB AS;919061227;BEDR;2017-07-03;2017-05-15;2017-05-25",
            ";")]
        [InlineData(
            "\"StatId\";\"StatUnitName\";\"parent_unit\";\"organistaional_form\";\"RegisterDate\";\"dateOfCommencement\";\"dateChangeOfOwner\"\n"
            + "\"919228741\";\"ALEX TRANSPORT\";\"919018828\";\"BEDR\";\"2017-07-03\";\"2017-06-04\";\n"
            + "\"919228768\";\"UNISOL UTEGLASS AS\";\"919146605\";\"BEDR\";;;\n"
            + "\"919228776\";\"PETBNB AS\";\"919061227\";\"BEDR\";\"2017-07-03\";\"2017-05-15\";\"2017-05-25\"",
            ";")]
        private void ShouldParseEntityFromUnquotedCommaString(string source, string delimiter)
        {
            var actual = CsvParser.GetParsedEntities(source, delimiter, string.Empty).ToArray();

            Assert.Equal(3, actual.Length);
            Assert.Equal("919061227", actual[2]["parent_unit"]);
        }

        [Theory]
        [InlineData(
            @"statId;name;activity1;employees;activityYear
920951287;LAST FRIDAY INVEST AS;62.020;100;2019
920951287;LAST FRIDAY INVEST AS;70.220;20;2018
920951287;LAST FRIDAY INVEST AS;52.292;10;2011
920951287;LAST FRIDAY INVEST AS;68.209;;;", ";")]
        private void ShouldParseEntityWithActivities(string source, string delimiter)
        {
            var mappings =
                "statId-StatId,name-Name,activity1-Activities.Activity.ActivityCategory.Code,employees-Activities.Activity.Employees,activityYear-Activities.Activity.ActivityYear";
            var actual = CsvParser.GetParsedEntities(source, delimiter, mappings).ToList();
            actual.Should().BeEquivalentTo(new List<IReadOnlyDictionary<string, object>>
            {
                new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>()
                    {
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                            {
                                {"ActivityCategory.Code", "62.020"},
                                {"Employees","100"},
                                {"ActivityYear","2019"}
                            }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                        {
                            {"ActivityCategory.Code", "70.220"},
                            {"Employees","20"},
                            {"ActivityYear","2018"}
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                        {
                            {"ActivityCategory.Code", "52.292"},
                            {"Employees","10"}
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>()
                        {
                            {"ActivityCategory.Code", "68.209"},
                        })
                    }}
                }
            });
            //Assert.Equal(3, actual.Length);
           // Assert.Equal("919061227", actual[2]["parent_unit"]);
        }
    }
}
