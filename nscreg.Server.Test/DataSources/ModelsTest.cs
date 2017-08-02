using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Utilities.Enums;
using Xunit;

namespace nscreg.Server.Test.DataSources
{
    public class ModelsTest
    {
        [Fact]
        private void SubmitMCreateEntityPriorityParseShouldWork()
        {
            const DataSourcePriority expected = DataSourcePriority.Trusted;
            var obj = new SubmitM {Priority = expected.ToString()};

            var actual = obj.CreateEntity().Priority;

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void SubmitMCreateEntityPriorityParseFailShouldReturnDefault()
        {
            var actual = new SubmitM {Priority = "non-existing value"}.CreateEntity().Priority;

            Assert.Equal(DataSourcePriority.NotTrusted, actual);
        }

        [Fact]
        private void SubmitMUpdateEntityPriorityParseShouldWork()
        {
            const DataSourcePriority expected = DataSourcePriority.Trusted;
            var actual = new DataSource { Priority = DataSourcePriority.Trusted };

            new SubmitM {Priority = expected.ToString()}.UpdateEntity(actual);

            Assert.Equal(expected, actual.Priority);
        }

        [Fact]
        private void SubmitMUpdateEntityPriorityParseFailShouldStayUnchanged()
        {
            var actual = new DataSource {Priority = DataSourcePriority.Trusted};

            new SubmitM { Priority = "non-existing value" }.UpdateEntity(actual);

            Assert.Equal(DataSourcePriority.Trusted, actual.Priority);
        }

        [Fact]
        private void SearchQueryMSetOrderByShouldWork()
        {
            const OrderRule expected = OrderRule.Desc;

            var obj = new SearchQueryM {OrderBy = expected.ToString()};

            Assert.Equal(expected, obj.OrderByValue);
        }

        [Fact]
        private void InitializePropertyInfoM()
        {
            var actual = new PropertyInfoM();

            Assert.NotNull(actual);
        }

        [Fact]
        private void InitializePropertyInfoMTwice()
        {
            var first = new PropertyInfoM();
            var second = new PropertyInfoM();

            Assert.NotNull(first);
            Assert.NotNull(second);
        }
    }
}
