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

        public void CheckRegionOrActivityContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId, List<int> activityCategoryList)
        {
            if (_userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator).Result) return;
            var regionIds = new List<int?> { regionId, actualRegionId, postalRegionId }.Where(x => x != null).Select(x => (int) x).ToList();
            CheckIfRegionContains(userId, regionIds);
            CheckIfActivityContains(userId, activityCategoryList);
        }

        public void CheckRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList)
        {
            if (_userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator).Result) return;
            CheckIfRegionContains(userId, regionIds);
            CheckIfActivityContains(userId, activityCategoryList);
        }

        public bool IsRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList)
        {
            try
            {
                CheckRegionOrActivityContains(userId, regionIds, activityCategoryList);
                return true;
            } catch (System.Exception e) when (e is BadRequestException)
            {
                return false;
            }
        }

        public void CheckIfRegionContains(string userId, List<int> regionIds)
        {
            var userRegionIds = _dbContext.UserRegions.Where(au => au.UserId == userId).Select(ur => ur.RegionId).ToList();

            if (userRegionIds.Count == 0)
                throw new BadRequestException(nameof(Resource.YouDontHaveEnoughtRightsRegion));

            var listRegions = regionIds.Where(x => !userRegionIds.Contains(x)).ToList();
            if (listRegions.Count > 0)
            {
                var regionNames = _dbContext.Regions.Where(x => listRegions.Contains(x.Id))
                    .Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2 }.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsRegion))} ({string.Join(",", regionNames.Distinct())})");
            }
        }

        public void CheckIfActivityContains(string userId, List<int> activityCategoryIds)
        {
            var activityCategoryUserIds = _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId)
                .Select(ur => ur.ActivityCategoryId).ToList();

            if (activityCategoryUserIds.Count == 0)
                throw new BadRequestException(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory));

            foreach (var activityCategoryId in activityCategoryIds)
            {
                if (!activityCategoryUserIds.Contains(activityCategoryId))
                {
                    var activityCategoryNames =
                        _dbContext.ActivityCategories.Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2, Id = x.Id }).FirstOrDefault(x => x.Id == activityCategoryId);

                    var langName = activityCategoryNames.GetString(CultureInfo.DefaultThreadCurrentCulture);
                    throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory))} ({langName})");
                }
            }
        }
    }
}
