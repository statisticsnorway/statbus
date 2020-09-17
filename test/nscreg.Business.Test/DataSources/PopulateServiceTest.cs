using FluentAssertions;
using nscreg.Business.Test.Base;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common;
using nscreg.TestUtils;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
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
        public async Task PopulateAsync_PersonMapping_Success()
        {
            var mappings =
    "statId-StatId,name-Name,activity1-Activities.Activity.ActivityCategory.Code,employees-Activities.Activity.Employees,activityYear-Activities.Activity.ActivityYear,addr1-Address.AddressPart1,PersonRole-Persons.Person.Role";

            var mappingsArray = mappings.Split(',').Select(vm =>
            {
                var pair = vm.Split('-');
                return (pair[0], pair[1]);
            }).ToArray();

            using (var context = InMemoryDb.CreateDbContext())
            {
                context.PersonTypes.Add(new PersonType { Name = "DIRECTOR" });
                await context.SaveChangesAsync();

                var populateService = new PopulateService(mappingsArray, DataSourceAllowedOperation.Create, DataSourceUploadTypes.StatUnits, StatUnitTypes.LegalUnit, context);

                var raw = new Dictionary<string, object>()
                {
                    { "StatId", "920951287"},
                    { "Name", "LAST FRIDAY INVEST AS" },
                    { "Address.AddressPart1", "TEST ADDRESS" },
                    { "Persons", new List<KeyValuePair<string, Dictionary<string, string>>>(){
                        new KeyValuePair<string, Dictionary<string, string>>("Person", new Dictionary<string, string>()
                            {
                                {"Role", "Director"},
                            })
                        }
                    },
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
                        }
                    }
                };


                var (popUnit, isNeW, errors) = await populateService.PopulateAsync(raw);


            }
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
