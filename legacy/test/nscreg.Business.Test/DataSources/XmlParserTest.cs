using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using FluentAssertions;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources
{
    public class XmlParserTest
    {
        [Fact]
        public void ShouldParseEntityWithActivityTest()
        {
            var xdoc = XDocument.Parse(
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>" +
                "<GetLegalUnits xmlns=\"http://sti.gov.kg/\">" +
                    "<LegalUnit>" +
                        "<StatId>920951287</StatId>" +
                        "<Name>LAST FRIDAY INVEST AS</Name>" +
                        "<Activities>" +
                            "<Activity>" +
                                "<ActivityYear>2019</ActivityYear>" +
                                "<CategoryCode>62.020</CategoryCode>" +
                                "<Employees>100</Employees>" +
                            "</Activity>" +
                            "<Activity>" +
                                 "<ActivityYear>2018</ActivityYear>" +
                                 "<CategoryCode>70.220</CategoryCode>" +
                                 "<Employees>20</Employees>" +
                            "</Activity>" +
                            "<Activity>" +
                                "<CategoryCode>52.292</CategoryCode>" +
                                "<Employees>10</Employees>" +
                            "</Activity>" +
                            "<Activity>" +
                                "<CategoryCode>68.209</CategoryCode>" +
                            "</Activity>" +
                        "</Activities>" +
                    "</LegalUnit>" +
                "<LegalUnit>" +
                    "<StatId>920951287</StatId>" +
                    "<Name>LAST FRIDAY INVEST AS</Name>" +
                "</LegalUnit>" +
                "<LegalUnit>" +
                    "<StatId>913123</StatId>" +
                    "<Name>LAST</Name>" +
                    "<Activities>" +
                        "<Activity>" +
                            "<ActivityYear>2019</ActivityYear>" +
                            "<CategoryCode>62.020</CategoryCode>" +
                            "<Employees>100</Employees>" +
                        "</Activity>" +
                        "<Activity>" +
                            "<ActivityYear>2018</ActivityYear>" +
                            "<CategoryCode>70.220</CategoryCode>" +
                            "<Employees>20</Employees>" +
                        "</Activity>" +
                        "<Activity>" +
                            "<CategoryCode>52.292</CategoryCode>" +
                            "<Employees>10</Employees>" +
                        "</Activity>" +
                        "<Activity>" +
                            "<CategoryCode>68.209</CategoryCode>" +
                        "</Activity>" +
                    "</Activities>" +
                "</LegalUnit>" +
                "</GetLegalUnits>");
            var mappings =
                "StatId-StatId,Name-Name,Activities.Activity.ActivityYear-Activities.Activity.ActivityYear,Activities.Activity.CategoryCode-Activities.Activity.ActivityCategory.Code,Activities.Activity.Employees-Activities.Activity.Employees";
            var array = mappings.Split(',').Select(vm =>
            {
                var pair = vm.Split('-');
                return (pair[0], pair[1]);
            }).ToArray();

            var actual = XmlParser.GetRawEntities(xdoc);
            var entitiesDictionary = actual.Select(x => XmlParser.ParseRawEntity(x, array)).ToArray();
            entitiesDictionary.Should().BeEquivalentTo(new List<IReadOnlyDictionary<string, object>>
            {
                new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>
                    {
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear","2019"},
                            {"ActivityCategory.Code", "62.020"},
                            {"Employees","100"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear","2018"},
                            {"ActivityCategory.Code", "70.220"},
                            {"Employees","20"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "52.292"},
                            {"Employees","10"}
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "68.209"},
                        })
                    }}
                },
                new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                },
                new Dictionary<string, object>()
                {
                    { "StatId", "913123"},
                    { "Name", "LAST" },
                    { "Activities", new List<KeyValuePair<string, Dictionary<string, string>>>
                    {
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear","2019"},
                            {"ActivityCategory.Code", "62.020"},
                            {"Employees","100"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityYear","2018"},
                            {"ActivityCategory.Code", "70.220"},
                            {"Employees","20"},

                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "52.292"},
                            {"Employees","10"}
                        }),
                        new KeyValuePair<string, Dictionary<string, string>>("Activity", new Dictionary<string, string>
                        {
                            {"ActivityCategory.Code", "68.209"},
                        })
                    }}
                }
            });
        }
    }
}
