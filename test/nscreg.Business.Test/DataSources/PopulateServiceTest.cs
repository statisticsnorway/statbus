using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Moq;
using Nest;
using nscreg.Business.Test.Base;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.TestUtils;
using Xunit;
using Xunit.Abstractions;

namespace nscreg.Business.Test.DataSources
{
    public class PopulateServiceTest : BaseTest
    {
        private const string _unitMapping = "StatId-StatId,Name-Name";
        private readonly (string, string)[] _array = _unitMapping
            .Split(',')
            .Select(vm =>
            {
                var pair = vm.Split('-');
                return (pair[0], pair[1]);
            }).ToArray();

        public PopulateServiceTest(ITestOutputHelper helper) : base(helper)
        {
        }

        [Fact]
        public async Task PopulateAsync_NewObjectOnAlter_ReturnsError()
        {
            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
            };

            using (var context = InMemoryDb.CreateDbContext())
            {
                var populateService = new PopulateService(_array, DataSourceAllowedOperation.Alter, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);

                Assert.True(isNeW && errors == $"StatUnit failed with error: {Resource.StatUnitIdIsNotFound} ({popUnit.StatId})");
            }
            
        }

        [Fact]
        public async Task PopulateAsync_ExistsObjectOnCreate_ReturnsError()
        {

            var raw = new Dictionary<string, object>()
            {
                {"StatId", "920951287"},
                {"Name", "LAST FRIDAY INVEST AS"},
            };
            var unit = new LegalUnit() {StatId = "920951287", Name = "LAST FRIDAY INVEST AS"};

            using (var context = InMemoryDb.CreateDbContext())
            {
                context.StatisticalUnits.Add(unit);
                await context.SaveChangesAsync();
                var populateService = new PopulateService(_array, DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);
                var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);

                Assert.True(!isNeW && errors == string.Format(Resource.StatisticalUnitWithSuchStatIDAlreadyExists, unit.StatId));
            }

        }


    }
}
