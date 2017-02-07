using System.Collections.ObjectModel;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;
using Xunit;
using static nscreg.Server.Test.InMemoryDb;

namespace nscreg.Server.Test
{
    public class ActivityServiceTest
    {
        [Fact]
        public void CreateTest()
        {
            using (var context = CreateContext())
            {
                AutoMapperConfiguration.Configure();
                new ActivityService(context).Create(new ActivityCreateM
                {
                    UnitId = 555,
                    ActivityType = ActivityTypes.Primary,
                    ActivityRevx = 111,
                    ActivityRevy = 222
                });

                Assert.IsType<Activity>(
                    context.Activities.Single(
                        x =>
                            x.UnitId == 555 && x.ActivityType == ActivityTypes.Primary && x.ActivityRevx == 111 &&
                            x.ActivityRevy == 222));
            }
        }

        [Fact]
        public void GetActivityByIdTest()
        {
            using (var context = CreateContext())
            {
                context.Activities.Add(new Activity {UnitId = 1, ActivityRevx = 22, ActivityRevy = 333});
                context.SaveChanges();
                Assert.IsType<Activity>(new ActivityService(context).GetActivityById(
                    context.Activities.Single(x => x.UnitId == 1 && x.ActivityRevx == 22 && x.ActivityRevy == 333)
                        .Id));
            }
        }

        [Fact]
        public void GetUnitActivitiesTest()
        {
            using (var context = CreateContext())
            {
                context.Activities.AddRange(new Collection<Activity>
                {
                    new Activity {UnitId = 1},
                    new Activity {UnitId = 1},
                    new Activity {UnitId = 2}
                });
                context.SaveChanges();

                var activities = new ActivityService(context).GetUnitActivities(1);

                Assert.Collection(activities,
                    a => { Assert.Equal(1, a.UnitId); },
                    b => { Assert.Equal(1, b.UnitId); });
            }
        }

        [Fact]
        public void GetAllActivitiesTest()
        {
            using (var context = CreateContext())
            {
                context.Activities.AddRange(new Collection<Activity>
                {
                    new Activity {UnitId = 1},
                    new Activity {UnitId = 1},
                    new Activity {UnitId = 2}
                });
                context.SaveChanges();

                var activities = new ActivityService(context).GetAllActivities();

                Assert.Collection(activities,
                    a => { Assert.Equal(1, a.UnitId); },
                    b => { Assert.Equal(1, b.UnitId); },
                    c => { Assert.Equal(2, c.UnitId); });
            }
        }

        [Fact]
        public void UpdateTest()
        {
            using (var context = CreateContext())
            {
                AutoMapperConfiguration.Configure();
                context.Activities.Add(new Activity
                {
                    UnitId = 123,
                    ActivityType = ActivityTypes.Ancilliary,
                });
                context.SaveChanges();
                new ActivityService(context).Update(new ActivityEditM
                {
                    Id =
                        context.Activities.Single(x => x.UnitId == 123 && x.ActivityType == ActivityTypes.Ancilliary).Id,
                    UnitId = 123,
                    ActivityType = ActivityTypes.Primary,
                    UpdatedBy = 11
                });

                Assert.IsType<Activity>(
                    context.Activities.Single(
                        x =>
                            x.UnitId == 123 && x.ActivityType == ActivityTypes.Primary && x.UpdatedBy == 11));
            }
        }

        [Fact]
        public void DeleteTest()
        {
            using (var context = CreateContext())
            {
                context.Activities.Add(new Activity {UnitId = 111});
                context.SaveChanges();
                new ActivityService(context).Delete(context.Activities.Single(x => x.UnitId == 111).Id);

                Assert.False(context.Activities.Any());
            }
        }
    }
}