using nscreg.Data.Constants;
using nscreg.Server.Models.DataSources;
using nscreg.Utilities.Enums;
using Xunit;

namespace nscreg.Server.Test.DataSources
{
    public class ModelsTest
    {
        [Fact]
        private void CreateMGetEntityPriorityParseShouldWork()
        {
            const DataSourcePriority expected = DataSourcePriority.Trusted;
            var obj = new CreateM {Priority = expected.ToString()};

            var actual = obj.GetEntity().Priority;

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void CreateMGetEntityPriorityParseFailShouldReturnDefault()
        {
            var actual = new CreateM {Priority = "not existing value"}.GetEntity().Priority;

            Assert.Equal(DataSourcePriority.NotTrusted, actual);
        }

        [Fact]
        private void SearchQueryMSetOrderByShouldWork()
        {
            const OrderRule expected = OrderRule.Desc;

            var obj = new SearchQueryM {OrderBy = expected.ToString()};

            Assert.Equal(expected, obj.OrderByValue);
        }
    }
}
