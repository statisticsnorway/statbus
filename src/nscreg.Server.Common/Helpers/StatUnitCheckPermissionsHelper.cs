using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Resources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// Класс-помощник для создания статистических единиц по правилам
    /// </summary>
    public partial class StatUnitCheckPermissionsHelper
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;

        public StatUnitCheckPermissionsHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
        }

        public void CheckRegionOrActivityContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId, List<ActivityM> activityCategoryList)
        {
            if (!_userService.IsInRoleAsync(userId, DefaultRoleNames.Employee).Result) return;
            CheckIfRegionContains(userId, regionId, actualRegionId, postalRegionId);
            CheckIfActivityContains(userId, activityCategoryList);
        }

        public bool IsRegionContains(string userId, int? regionId, int? actualRegionId = null, int? postalRegionId = null)
        {
            var regionIds = _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToList();

            if (regionIds.Count == 0)
                return false;
            var listRegions = new List<int>();
            if (regionId != null && !regionIds.Contains((int)regionId))
                listRegions.Add((int)regionId);
            if (actualRegionId != null && !regionIds.Contains((int)actualRegionId))
                listRegions.Add((int)actualRegionId);
            if (postalRegionId != null && !regionIds.Contains((int)postalRegionId))
                listRegions.Add((int)postalRegionId);
            if (listRegions.Count > 0)
            {
                return false;
            }
            return true;
        }

        public void CheckIfRegionContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId)
        {
            var regionIds = _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToList();

            if (regionIds.Count == 0)
                throw new BadRequestException(nameof(Resource.YouDontHaveEnoughtRightsRegion));
            var listRegions = new List<int>();
            if (regionId != null && !regionIds.Contains((int)regionId))
                listRegions.Add((int)regionId);
            if (actualRegionId != null && !regionIds.Contains((int)actualRegionId))
                listRegions.Add((int)actualRegionId);
            if (postalRegionId != null && !regionIds.Contains((int)postalRegionId))
                listRegions.Add((int)postalRegionId);
            if (listRegions.Count > 0)
            {
                var regionNames = _dbContext.Regions.Where(x => listRegions.Contains(x.Id))
                    .Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2 }.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsRegion))} ({string.Join(",", regionNames.Distinct())})");
            }
        }

        public void CheckIfActivityContains(string userId, List<ActivityM> activityCategoryList)
        {
            foreach (var activityCategory in activityCategoryList)
            {
                if (activityCategory?.ActivityCategoryId == null)
                    throw new BadRequestException(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory));

                var activityCategoryUserIds = _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId)
                    .Select(ur => ur.ActivityCategoryId).ToList();
                if (activityCategoryUserIds.Count == 0 || !activityCategoryUserIds.Contains(activityCategory.ActivityCategoryId))
                {
                    var activityCategoryNames =
                        _dbContext.ActivityCategories.Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2, Id = x.Id }).FirstOrDefault(x => x.Id == activityCategory.ActivityCategoryId);

                    var langName = activityCategoryNames.GetString(CultureInfo.DefaultThreadCurrentCulture);
                    throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory))} ({langName})");
                }
            }
        }
    }
}
