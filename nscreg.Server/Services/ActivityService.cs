using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;

namespace nscreg.Server.Services
{
//    public class ActivityService
//    {
//        private ReadContext ReadCtx { get; }
//
//        private NSCRegDbContext DbContext { get; }
//
//        public ActivityService(NSCRegDbContext context)
//        {
//            DbContext = context;
//            ReadCtx = new ReadContext(context);
//        }
//
//        public void Create(ActivityCreateM data)
//        {
//            var activity = Mapper.Map<ActivityCreateM, Activity>(data);
//            DbContext.Activities.Add(activity);
//            DbContext.SaveChanges();
//        }
//
//        public Activity GetActivityById(int activityId) => ReadCtx.Activities.FirstOrDefault(x => x.Id == activityId);
//
//        public ICollection<Activity> GetUnitActivities(int unitId)
//            => ReadCtx.Activities.Where(x => x.UnitId == unitId).ToList();
//
//        public ICollection<Activity> GetAllActivities() => ReadCtx.Activities.ToList();
//
//        public void Update(ActivityEditM data)
//        {
//            var activity = DbContext.Activities.Single(x => x.Id == data.Id);
//            Mapper.Map(data, activity);
//            DbContext.SaveChanges();
//        }
//
//        public void Delete(int activityId)
//        {
//            var activity = DbContext.Activities.Single(x => x.Id == activityId);
//            DbContext.Activities.Remove(activity);
//            DbContext.SaveChanges();
//        }
//    }
}
