using System.Linq;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources
{
    public class CsvParserTest
    {
        [Theory]
        [InlineData(
            "TaxId,ExternalId,StatId,StatUnitName,parent_unit,organistaional_form,RegisterDate,dateOfCommencement,dateChangeOfOwner\n"
            + "91922874121,919228741,919228741,ALEX TRANSPORT,919018828,BEDR,2017-07-03,2017-06-04\n"
            + "91922874121,9192287412,919228768,UNISOL UTEGLASS AS,919146605,BEDR,,\n"
            + "919228741123,919228741,919228776,PETBNB AS,919061227,BEDR,2017-07-03,2017-05-15,2017-05-25",
            ",")]
        [InlineData(
            "TaxId;ExternalId;StatId;StatUnitName;parent_unit;organistaional_form;RegisterDate;dateOfCommencement;dateChangeOfOwner\n"
            + "91922874135;9192287413;919228741;ALEX TRANSPORT;919018828;BEDR;2017-07-03;2017-06-04\n"
            + "9192287414;9192287412;919228768;UNISOL UTEGLASS AS;919146605;BEDR;;\n"
            + "919228741;9192287413;9192287764;PETBNB AS;919061227;BEDR;2017-07-03;2017-05-15;2017-05-25",
            ";")]
        [InlineData(
            "\"TaxId\";\"ExternalId\";\"StatId\";\"StatUnitName\";\"parent_unit\";\"organistaional_form\";\"RegisterDate\";\"dateOfCommencement\";\"dateChangeOfOwner\"\n"
            + "\"9192287419\";\"9192287431\";\"919228741\";\"ALEX TRANSPORT\";\"919018828\";\"BEDR\";\"2017-07-03\";\"2017-06-04\"\n"
            + "\"91922874109\";\"9192287461\";\"919228768\";\"UNISOL UTEGLASS AS\";\"919146605\";\"BEDR\";;n"
            + "\"919228741009\";\"9192287413\";\"919228776\";\"PETBNB AS\";\"919061227\";\"BEDR\";\"2017-07-03\";\"2017-05-15\";\"2017-05-25\"",
            ";")]
        private void ShouldParseEntityFromUnquotedCommaString(string source, string delimiter)
        {
            //var actual = CsvParser.GetParsedEntities(source, delimiter).ToArray();

            //Assert.Equal(3, actual.Length);
            //Assert.Equal("919061227", actual[2]["parent_unit"]);
        }
    }
}
