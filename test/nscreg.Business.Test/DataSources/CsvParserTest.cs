using System.Linq;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources
{
    public class CsvParserTest
    {
        [Theory]
        [InlineData(
            "statID,name,parent_unit,organistaional_form,RegisterDate,dateOfCommencement,dateChangeOfOwner\n"
            + "919228741,ALEX TRANSPORT,919018828,BEDR,2017-07-03,2017-06-04,\n"
            + "919228768,UNISOL UTEGLASS AS,919146605,BEDR,,,\n"
            + "919228776,PETBNB AS,919061227,BEDR,2017-07-03,2017-05-15,2017-05-25",
            ",")]
        [InlineData(
            "statID;name;parent_unit;organistaional_form;RegisterDate;dateOfCommencement;dateChangeOfOwner\n"
            + "919228741;ALEX TRANSPORT;919018828;BEDR;2017-07-03;2017-06-04;\n"
            + "919228768;UNISOL UTEGLASS AS;919146605;BEDR;;;\n"
            + "919228776;PETBNB AS;919061227;BEDR;2017-07-03;2017-05-15;2017-05-25",
            ";")]
        [InlineData(
            "\"statID\";\"name\";\"parent_unit\";\"organistaional_form\";\"RegisterDate\";\"dateOfCommencement\";\"dateChangeOfOwner\"\n"
            + "\"919228741\";\"ALEX TRANSPORT\";\"919018828\";\"BEDR\";\"2017-07-03\";\"2017-06-04\";\n"
            + "\"919228768\";\"UNISOL UTEGLASS AS\";\"919146605\";\"BEDR\";;;\n"
            + "\"919228776\";\"PETBNB AS\";\"919061227\";\"BEDR\";\"2017-07-03\";\"2017-05-15\";\"2017-05-25\"",
            ";")]
        private void ShouldParseEntityFromUnquotedCommaString(string source, string delimiter)
        {
            var actual = CsvParser.GetParsedEntities(source, delimiter).ToArray();

            Assert.Equal(3, actual.Length);
            Assert.Equal("919061227", actual[2]["parent_unit"]);
        }
    }
}
